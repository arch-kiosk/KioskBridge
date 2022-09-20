//
//  KioskBridgeView.swift
//  KioskBridge Main Screen
//
//  Created by Lutz Klein on 8/20/22.
//

import SwiftUI

enum APIError: Error {
    case runtimeError(String)
}

struct KioskBridgeView: View {
    @StateObject var app_state: AppState = AppState()
    @State private var settings_shown = false
    @State private var runningTask: Task<Void, Never>?
    @State private var downloadTask: URLSessionDownloadTask?
    @State private var taskProgress: Double = 0
    @State private var observation: NSKeyValueObservation?
    @State private var isShareSheetPresented:Bool = false

    fileprivate func connectToKiosk() {
        if ($app_state.debug.wrappedValue) {
            return
        }
        if let oldRunningTask = runningTask {
            oldRunningTask.cancel()
        }
        runningTask = Task {
            do {
                try await loginToKiosk()
                try await getDockInfo()
            } catch {
                print("Error in connectToKiosk: \(error)")
            }
            runningTask = nil
        }
    }
    
    var body: some View {
        
            VStack {
                VStack {
                    Section {
                        Text("KioskBridge")
                            .font(.title)
                        Text(getStatusText())
                            .font(.title2)
                        Button(app_state.get_state_text())
                        {
                            print("resetting app_state")
                            app_state.state = .idle
                            app_state.save()
                        }

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading)

                    SettingsDisplayView(settings: app_state.settings, settings_shown: $settings_shown)
                }
                .background(getStatusColor())
                if downloadTask != nil {
                    ProgressView("Transfering ...", value: taskProgress, total: 1)
                                .progressViewStyle(LinearProgressViewStyle())
                                .padding()
                } else {
                    DockOptionsView(app_state: app_state, kiosk_bridge_view: self)
                }

                Divider()
                Spacer()
            }
            .sheet(isPresented: $settings_shown, content: {
                SettingsView(settings: app_state.settings)
                    .onDisappear() {
                        connectToKiosk()
                    }
            })
            .sheet(isPresented: $isShareSheetPresented) {
                ActivityView(isSheetPresented:$isShareSheetPresented, bridgeView:self, activityItems: [getDocumentUrl()!], applicationActivities: [])
                    }
            .navigationTitle("KioskBridge")
            .onAppear() {
                connectToKiosk()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    func triggerTransition(transition_name: String) {
        if transition_name.contains("download") {
            try! transitionDownload()
            return
        }
        if transition_name.contains("send") {
            isShareSheetPresented = true
//            try! transitionSendToFileMaker()
            return
        }
        print("unknown transition triggered")

    }

    
    struct DockOptionsView: View {
        @ObservedObject var app_state: AppState

        var kiosk_bridge_view: KioskBridgeView
        
        var body: some View {
            VStack {
                ForEach($app_state.transitions , id: \.self) { s in
                    Button(action: {
                        kiosk_bridge_view.triggerTransition(transition_name: s.wrappedValue)
                    }, label: {
                        HStack {
                            Text(s.wrappedValue)
                            if (s.wrappedValue.contains("send")) {
                                Text("(\(kiosk_bridge_view.getDocumentUrl()?.lastPathComponent ?? "no file"))")
                            }
                        }
                    })
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemFill))
                    .padding()
                }
            }
        }
    }

    func getStatusColor() -> Color {
        switch $app_state.api_state.wrappedValue {
        case .connected, .docked: return $app_state.app_error_state.wrappedValue == "" ? Color.green : Color.red
        case .unauthorized, .nodock, .wrongdocktype: return Color.red
        case .disconnected, .connecting, .error:
            return Color.gray
        }
    }
    
    func getStatusText() -> String {
        let app_error_state = $app_state.app_error_state.wrappedValue
        let settings = app_state.settings
        switch $app_state.api_state.wrappedValue {
        case .connected: return "Connected to \(settings.server_url)"
        case .docked: return app_error_state == "" ? "Docked to \(settings.server_url)/\(settings.dock_id)" : app_error_state
        case .unauthorized: return "User not authorized"
        case .nodock: return "Dock inaccessible"
        case .wrongdocktype: return "\(settings.dock_id) is not a filemaker recording dock"
        case .connecting: return "Connecting ..."
        case .disconnected, .error:
            return "No connection to Kiosk"
        }
    }

    func loginToKiosk() async throws {
        let settings = app_state.settings
        app_state.api_token = ""
        app_state.setApiState(api_state: .connecting)
        let url_str = "\(settings.server_url)\(api_login_path)"
        guard let url = URL(string: url_str) else {
            throw(APIError.runtimeError("Cannot build url"))
        }
        print("connecting to Kiosk at \(url)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let loginData = ApiLogin(userid: settings.user_id,
                                 password: settings.password)
        
        let jsonData = try? JSONEncoder().encode(loginData)
        request.httpBody = jsonData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                app_state.setApiState(api_state: httpResponse.statusCode == 401 ?  .unauthorized : .error)
                print ("httpResponse.statusCode: \(httpResponse.statusCode)")
            } else {
                guard let loginResponse = try? JSONDecoder().decode(ApiLoginResponse.self, from: data) else {
                        throw(APIError.runtimeError("Cannot decode response"))
                    }
                app_state.api_token = loginResponse.token
                print("Token: \(app_state.api_token)")
                app_state.setApiState(api_state: .connected)
            }
        } catch {
            app_state.setApiState(api_state: .error)
        }
    }

    func getDockInfo() async throws {
        let settings = app_state.settings
        guard $app_state.api_state.wrappedValue >= .connected, app_state.api_token != "" else {
            return
        }
        
        let url_str = "\(settings.server_url)\(api_dock_path)?dock_id=\(settings.dock_id)"
        guard let url = URL(string: url_str) else {
            throw(APIError.runtimeError("Cannot build url"))
        }
        
        print("docking to \(url)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Bearer <<access-token>>",
            forHTTPHeaderField: "Authentication"
        )
        let sessionConfiguration = URLSessionConfiguration.default // 5

        sessionConfiguration.httpAdditionalHeaders = [
            "Authorization": "Bearer \(app_state.api_token)"
        ]
        let session = URLSession(configuration: sessionConfiguration)
        
        do {
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                print ("httpResponse.statusCode: \(httpResponse.statusCode)")
                switch (httpResponse.statusCode) {
                    case 401: app_state.setApiState(api_state: .unauthorized)
                    case 404: app_state.setApiState(api_state: .nodock)
                    default: app_state.setApiState(api_state: .error)
                }
            } else {
                guard let dockResponse = try? JSONDecoder().decode(ApiDockResponse.self, from: data) else {
                        throw(APIError.runtimeError("Cannot decode response"))
                    }
                print("Dock description: \(dockResponse.description)")
                if (dockResponse.workstation_class == "KioskFileMakerWorkstation") {
                    app_state.setApiState(api_state: .docked)
                    app_state.setDockStateFromStr(dock_state_str: dockResponse.state_text)
                }
                else {
                    print(dockResponse)
                    app_state.setApiState(api_state: .wrongdocktype)
                }
            }
        } catch {
            print("Error in getDockInfo: \(error)")
            app_state.setApiState(api_state: .error)
        }
    }

    func transitionDownload() throws {
        guard $app_state.api_state.wrappedValue >= .docked, app_state.api_token != "", app_state.state != .needs_upload else {
            return
        }
        downloadTask?.cancel()
        downloadTask = nil
        observation?.invalidate()
        taskProgress = 0
        let route = api_workstation_download.replacingOccurrences(of: "<dock-id>", with: app_state.settings.dock_id)
        let url_str = "\(app_state.settings.server_url)\(route)"
        guard let url = URL(string: url_str) else {
            throw(APIError.runtimeError("Cannot build url for file download"))
        }
        
        print("downloading from \(url)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Bearer <<access-token>>",
            forHTTPHeaderField: "Authentication"
        )
        let sessionConfiguration = URLSessionConfiguration.default

        sessionConfiguration.httpAdditionalHeaders = [
            "Authorization": "Bearer \(app_state.api_token)"
        ]
        let session = URLSession(configuration: sessionConfiguration)
        downloadTask = session.downloadTask(with: url) { localURL, urlResponse, error in
            print(error ?? "no error when downloading")
            guard let urlResponse = urlResponse else {
                print("no urlResponse")
                return
            }
            guard let filename = urlResponse.suggestedFilename else {
                print("no suggested filename")
                return
            }
            guard let localURL = localURL else {
                print("no local url")
                return
            }
            do {
                observation?.invalidate()
                downloadTask = nil
                try clearAllDocuments()

                let documentsURL = try
                    FileManager.default.url(for: .documentDirectory,
                                            in: .userDomainMask,
                                                appropriateFor: nil,
                                                create: false)
                let savedURL = documentsURL.appendingPathComponent(filename)
                let fm = FileManager.default
                
                try fm.moveItem(at: localURL, to: savedURL)
                DispatchQueue.main.async {
                    app_state.state = .downloaded
                    app_state.save()
                }
            } catch {
                print("Error in transitionDownload: \(error)")
            }
        }
        observation = downloadTask!.progress.observe(\.fractionCompleted) { observationProgress, _ in
            DispatchQueue.main.async {
                taskProgress = observationProgress.fractionCompleted
            }
        }
        downloadTask!.resume()
    }
    
    func getDocumentUrl() -> URL? {
        let fm = FileManager.default
        do {
            let documentsUrl = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false)
            
            let documents = try fm.contentsOfDirectory(atPath: documentsUrl.path)
            for doc in documents {
                let docPath = documentsUrl.appendingPathComponent(doc)
                return docPath
            }
        } catch {
            print("Error in getDocumentURL: \(error)")
        }
        return nil
    }
    
    func clearAllDocuments() throws {
        let fm = FileManager.default
        let documentsUrl = try FileManager.default.url(
            for: .documentDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: false)

        let documents = try fm.contentsOfDirectory(atPath: documentsUrl.path)
        for doc in documents {
            let docPath = documentsUrl.appendingPathComponent(doc)
            print("Deleting file \(docPath)")
            try fm.removeItem(at: docPath)
        }
    }
    
//    func transitionSendToFileMaker() throws {
//        guard let file = getDocumentUrl() else {
//            print("no file to send")
//            return
//        }
//        let items = [file]
//        let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
//
//        present(ac, animated: true, completion: nil)
//    }
//
}

struct ActivityView: UIViewControllerRepresentable {
    @Binding var isSheetPresented:Bool
    var bridgeView: KioskBridgeView
    
    var activityItems: [Any]
    var applicationActivities: [UIActivity]?
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<ActivityView>) -> UIActivityViewController {
        let ac = UIActivityViewController(activityItems: activityItems,
                            applicationActivities: applicationActivities)
        ac.completionWithItemsHandler = {
            (activityType: UIActivity.ActivityType?, completed:
                                        Bool, arrayReturnedItems: [Any]?, error: Error?) in
            isSheetPresented = false;
            
        }
        return ac;
   }
    
   func updateUIViewController(_ uiViewController: UIActivityViewController,
                               context: UIViewControllerRepresentableContext<ActivityView>) {}
   }

struct SettingsDisplayView: View {
    @ObservedObject var settings: KioskBridgeSettings
    @Binding var settings_shown: Bool
    
    var body: some View {
        HStack {
            Label("\(settings.user_id)", systemImage: settings.user_image)
                .padding(.all)
            Spacer()
            Label("\(settings.dock_id)", systemImage: settings.dock_image)
                .padding(.all)
            Spacer()
            Button() {
                settings_shown = true
            }
            label: {
                Text("edit")
            }
            .padding(.all)
            }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let settings = KioskBridgeSettings()
        settings.server_url = "192.168.1.228:5000"
        settings.user_id = "lkh"
        settings.dock_id = "x1lk"
        let app_state = AppState()
        app_state.setApiState(api_state: .docked)
        app_state.setDockStateFromStr(dock_state_str: "in the field")
        app_state.process_app_state()
        app_state.transitions = ["download", "upload"]
        app_state.debug = true
        app_state.settings = settings
        return KioskBridgeView(app_state: app_state)
    }
}
