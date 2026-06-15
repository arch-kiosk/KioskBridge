//
//  KioskBridgeView.swift
//  KioskBridge Main Screen
//
//  Created by Lutz Klein on 8/20/22.
//

import SwiftUI
import os
import UniformTypeIdentifiers

extension Bundle {
    var releaseVersionNumber: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }
    var buildVersionNumber: String? {
        return infoDictionary?["CFBundleVersion"] as? String
    }
}

let version: String = Bundle.main.releaseVersionNumber!

enum AnError: Error {
    case runtimeError(String)
}
struct RuntimeError: LocalizedError {
    let description: String

    init(_ description: String) {
        self.description = description
    }

    var errorDescription: String? {
        description
    }
}
enum APIError: Error {
    case runtimeError(String)
}
extension URL {
    var isDirectory: Bool {
       (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}
struct KioskBridgeView: View {
    @StateObject var app_state: AppState = AppState()
    @State private var settings_shown = false
    @State private var runningTask: Task<Void, Never>?
    @State private var downloadTask: URLSessionDownloadTask?
    @State private var uploadTask: URLSessionDataTask?
    @State private var taskProgress: Double = 0
    @State private var observation: NSKeyValueObservation?
    @State private var isShareSheetPresented:Bool = false
    @State private var alertShown = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""
    @State var transitioning: Bool = false
    @State var memoryUsed: String = ""
    @Binding var openedUrl: URL?
    @State var askForSuccessfulShare = false
    @Environment(\.scenePhase) var scenePhase
    let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    private static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier!,
            category: String(describing: KioskBridgeView.self))
            
    fileprivate func connectToKiosk(dockInfoOnly: Bool = false) {

        Self.logger.notice("Connecting to Kiosk at \(app_state.settings.server_url, privacy: .public)")
        if ($app_state.debug.wrappedValue) {
            return
        }
        if let oldRunningTask = runningTask {
            oldRunningTask.cancel()
        }
        runningTask = Task {
            do {
                if (!dockInfoOnly) {
                    try await loginToKiosk()
                }
                try await getDockInfo()
            } catch {
                Self.logger.error("Connecting to Kiosk failed: \(error, privacy: .public)")
                print("Error in connectToKiosk: \(error)")
                alertMessage = "Error in connectToKiosk: \(error). This should not have happened. Please get support."
                alertTitle = "Error connecting to Kiosk"
                alertShown = true
                
            }
            runningTask = nil
        }
    }
        
    var body: some View {
            VStack {
                VStack {
                    Section {
                        HStack {
                            Image("kiosk-spider-zigzag-transparent")
                                .resizable()
                                .frame(width: 64.0, height: 64.0)
                            Text("Kiosk Bridge \(version)")
                                .font(.title)
                            Spacer()
                            Label("\(memoryUsed)", systemImage: "")
                                .padding(.horizontal)
                        }
                        .padding(.top)
                        SettingsDisplayView(settings: app_state.settings, settings_shown: $settings_shown)
                            .padding(.bottom)

                        Button("\(getStatusText()) (Press to refresh connection)") {
                            connectToKiosk()
                        }
                        .font(.title2)

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading)
                    Divider()
                    Text("Bridge is \(app_state.get_state_text())")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.all)

                }
                .background(getStatusColor())
                if downloadTask != nil || uploadTask != nil {
                    ProgressView("On it ...", value: taskProgress, total: 1)
                                .progressViewStyle(LinearProgressViewStyle())
                                .padding()
                } else {
                    DockOptionsView(app_state: app_state, kiosk_bridge_view: self)
                }

                Divider()
                Spacer()
            }
            .sheet(isPresented: $settings_shown, content: {
                SettingsView(settings: app_state.settings, appState: app_state, logs: LogStore())
                    .onDisappear() {
                        if (app_state.state == .idle) {
                            try?clearAllDocuments()
                            try?clearAllDocuments(InBox: true)
                        }
                        connectToKiosk()
                    }
            })
            .sheet(isPresented: $isShareSheetPresented) {
                ActivityView(isSheetPresented:$isShareSheetPresented, bridgeView:self, activityItems: [getDocumentUrl()!], applicationActivities: []).onDisappear() {
//                    askUserIfSharingSuccessful()
                      isShareSheetPresented = false
                }.onAppear() {
                    transitionSentToFileMaker()
                }
            }
            .alert(isPresented: $alertShown) {
                        Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("Got it!")))
                    }
//            .alert("Did you successfully share the database with FileMaker?", isPresented: $askForSuccessfulShare) {
//                Button("Yes") {
//                    transitionSentToFileMaker()
//
//                }
//                Button("No") {
//                    askForSuccessfulShare = false
//                }
//            }
            .navigationTitle("KioskBridge")
            .onAppear() {
                connectToKiosk()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: openedUrl) { newValue in
                Self.logger.info("openedUrl changed")
                if (newValue != nil) {
                        processIncomingFile()
                }
            }
            .onChange(of: scenePhase) { newPhase in
                            if newPhase == .active {
                                connectToKiosk()
                            } else if newPhase == .inactive {
                                print("Inactive")
                            } else if newPhase == .background {
                                print("Background")
                            }
                        }
            .onReceive(timer) { input in
                refreshMemoryUsage()
                if (!settings_shown &&
                    !isShareSheetPresented && downloadTask == nil && uploadTask == nil) {
                    if (app_state.api_state > .connected ) {
                        print( input )
                        connectToKiosk(dockInfoOnly: true)
                    }
                }
            }
    }
    
    
    func refreshMemoryUsage(){
        // The `TASK_VM_INFO_COUNT` and `TASK_VM_INFO_REV1_COUNT` macros are too
        // complex for the Swift C importer, so we have to define them ourselves.
        let TASK_VM_INFO_COUNT = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        guard let offset = MemoryLayout.offset(of: \task_vm_info_data_t.min_address) else {
            memoryUsed  =  ""
            return
        }
        let TASK_VM_INFO_REV1_COUNT = mach_msg_type_number_t(offset / MemoryLayout<integer_t>.size)
        var info = task_vm_info_data_t()
        var count = TASK_VM_INFO_COUNT
        let kr = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard
            kr == KERN_SUCCESS,
            count >= TASK_VM_INFO_REV1_COUNT
        else { 
            memoryUsed  =  ""
            return
        }
        
        let usedBytes = Float(info.phys_footprint)
        let usedBytesInt: UInt64 = UInt64(usedBytes)
        let usedMB = usedBytesInt / 1024 / 1024
        memoryUsed  = "\(usedMB) MB memory used"
    }

    func transitionSentToFileMaker() {
        app_state.sentFileName = getDocumentUrl()!.lastPathComponent
        print("app state changed to .sent_to_filemaker: \(app_state.sentFileName)")
        app_state.state = .sent_to_filemaker
        app_state.save()
        askForSuccessfulShare = false
        do {
            try clearAllDocuments(InBox: true)
        } catch {
            print(error)
        }
    }
    
    func askUserIfSharingSuccessful() {
        askForSuccessfulShare = true
    }
    
    
    func processIncomingFile() {
        if (openedUrl != nil) {
            isShareSheetPresented = false
            Self.logger.notice("Received file: \(openedUrl!.absoluteString)")
            self.alertTitle = ""
            self.alertMessage = ""
            
            do {
                if (app_state.state == .sent_to_filemaker ||
                    app_state.state == .needs_upload ||
                    (app_state.state == .is_uploaded && app_state.dock_state == .uploaded) ||
                    (app_state.settings.unsafe_mode && app_state.dock_state == .prepared_for_download)
                ) {

                    //Check if filename matches
                    let receivedFileName = openedUrl!.lastPathComponent
                    if !app_state.settings.unsafe_mode && receivedFileName != app_state.sentFileName {
                        let sentFileNameWithoutExt = app_state.sentFileName.lowercased().replacingOccurrences(of: ".fmp12", with: "")
                        if receivedFileName.lowercased().contains(sentFileNameWithoutExt) {
                            self.alertTitle = "Please try again"
                            self.alertMessage = "The received file's name (\(receivedFileName)) does not match the name of the file that had been sent to FileMaker (\(app_state.sentFileName)). This can be due to an earlier internal error, so please try to send the file again after you closed this message."
                            throw AnError.runtimeError("suspicious filename")
                        } else {
                            self.alertTitle = "This doesn't look right"
                            self.alertMessage = "The received file's name (\(receivedFileName)) does not match the name of the file that had been sent to FileMaker (\(app_state.sentFileName)). Please try again with the correct file. "
                            throw AnError.runtimeError("wrong file")
                        }
                    }
                    try clearAllDocuments()

                    //copy incoming file to stored file
                    do {
                        //erase existing file

                        let fm = FileManager.default
                        var docUrl = try FileManager.default.url(
                            for: .documentDirectory,
                            in: .userDomainMask,
                            appropriateFor: nil,
                            create: false)
                        docUrl.appendPathComponent(receivedFileName)
                        
                        do {
                            try fm.moveItem(at: openedUrl!, to: docUrl)
                        } catch {
                            Self.logger.error("Error when moving the file to \(docUrl.absoluteString): \(error.localizedDescription)")
                            throw error
                        }
                        Self.logger.notice("File moved to: \(docUrl.path)")

                        print("File moved to \(docUrl.path)")
                        let attributes = try FileManager.default.attributesOfItem(atPath: docUrl.path)
                        let size = attributes[.size] as? Double ?? 0
                        Self.logger.notice("FileSize: \(size)")
                        if (size < 10000000) {
                            throw RuntimeError("The file \(docUrl.path) is suspiciously small. Something isn't right here.")
                        }
                        app_state.state = .needs_upload
                        app_state.save()
                        self.alertTitle = "Thanks for the file"
                        self.alertMessage = "The file has been successfully received from FileMaker and looks right, as far as I can tell."
                        DispatchQueue.main.async {
                            self.alertShown = true
                        }
                    } catch {
                        self.alertTitle = "Internal Error"
                        self.alertMessage = "The received file could not be stored or processed (\(error.localizedDescription)). Perhaps try again?"
                        throw error
                    }
                    
                } else {
                    self.alertTitle = "Can't deal with this file"
                    self.alertMessage = "A file has been sent to KioskBridge but no file was expected in the current state of the dock! File dismissed."
                    throw AnError.runtimeError("File received at wrong stage")
                }
            } catch {
                print(error)
                Self.logger.error("processIncomingFile: \(error, privacy: .public)")
                if self.alertTitle != "" {
                    DispatchQueue.main.async {
                        self.alertShown = true
                    }
                }

            }
        }
        openedUrl = nil
        try?clearAllDocuments(InBox: true)
    }
    
    func triggerTransition(transition_name: String) {
        Self.logger.notice("Triggering Transition \(transition_name, privacy: .public)")
        if transition_name.contains("download") {
            try! transitionDownload()
            app_state.transitioning = false
            return
        }
        if transition_name.contains("send") {
            isShareSheetPresented = true
            app_state.transitioning = false
            return
        }
        if transition_name.contains("upload") {
            transitionUpload()
            return
        }
        if transition_name.contains("connect") {
            connectToKiosk()
            app_state.transitioning = false
            return
        }
        Self.logger.error("Unknown Transition \(transition_name, privacy: .public)")
        app_state.transitioning = false

    }

    
    struct DockOptionsView: View {
        @ObservedObject var app_state: AppState

        var kiosk_bridge_view: KioskBridgeView
        
        var body: some View {
            VStack {
                ForEach($app_state.transitions , id: \.self) { s in
                    Button(action: {
                        app_state.transitioning = true
                        kiosk_bridge_view.triggerTransition(transition_name: s.wrappedValue)
                    }, label: {
                        HStack {
                            Text(s.wrappedValue)
                            if (s.wrappedValue.contains("send")) {
                                Text("(\(kiosk_bridge_view.getDocumentUrl()?.lastPathComponent ?? "no file"))")
                            }
                        }
                    })
                    .disabled(app_state.transitioning)
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
        case .connected, .docked: return $app_state.app_error_state.wrappedValue == "" ? Color("urap_green") : ($app_state.app_error_is_warning.wrappedValue ?  Color("sand") : Color("redish"))
        case .unauthorized, .nodock, .wrongdocktype: return Color("redish")
        case .disconnected, .connecting, .error:
            return Color("urap_grey")
        }
    }
    
    func getStatusText() -> String {
        let app_error_state = $app_state.app_error_state.wrappedValue
        let settings = app_state.settings
        switch $app_state.api_state.wrappedValue {
        case .connected: return "Connected to \(settings.server_url)"
        case .docked: return app_error_state == "" ? "Docked to \(settings.server_url)/\(settings.dock_id)" : app_error_state
        case .unauthorized: return "User not authorized"
        case .nodock: return "Dock inaccessible. Please check your settings."
        case .wrongdocktype: return "\(settings.dock_id) is not a filemaker recording dock"
        case .connecting: return "Connecting ..."
        case .disconnected, .error:
            return "No connection to Kiosk. Please check your settings."
        }
    }

    func loginToKiosk() async throws {
        let settings = app_state.settings
        app_state.api_token = ""
        app_state.dock_state = .unknown
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
                app_state.csrf_token = loginResponse.csrf
                print("Token: \(app_state.api_token)")
                print("CSRF Token: \(app_state.csrf_token)")
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
        
        let url_str = "\(settings.server_url)\(api_dock_path)?dock_id=\(settings.dock_id)".replacingOccurrences(of: " ", with: "%20")
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
                    if (app_state.state == .is_uploaded && app_state.dock_state != .uploaded)
                        || (app_state.state == .downloaded && app_state.dock_state != .prepared_for_download)
                        || (app_state.state == .needs_upload && app_state.dock_state == .not_ready){
                        app_state.state = .idle
                        app_state.save()
                    } else {
                    }

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
        
        Self.logger.error("Downloading from \(url, privacy: .public)")

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
            observation?.invalidate()
            downloadTask = nil
            guard let urlResponse = urlResponse else {
                alertTitle = "The download wasn't sucessful"
                alertMessage = "The download's did not come back with a urlResponse. Something is wrong here. This should not happen."
                Self.logger.error("The download's did not come back with a urlResponse. Something is wrong here. This should not happen.")
                alertShown = true
                return
            }
            if let httpResponse = urlResponse as? HTTPURLResponse, httpResponse.statusCode != 200 {
                alertTitle = "The download wasn't sucessful"
                alertMessage = "The server did not send the file (http error code \(httpResponse.statusCode)."
                Self.logger.error("The server did not send the file (http error code \(httpResponse.statusCode, privacy: .public).")
                alertShown = true
                return
            }

            guard let filename = urlResponse.suggestedFilename else {
                alertTitle = "The download wasn't sucessful"
                alertMessage = "The download's response did not have a suggestedFilename attribute. Something is wrong here. This should not happen."
                Self.logger.error("The download's response did not have a suggestedFilename attribute. Something is wrong here. This should not happen.")
                alertShown = true
                return
            }
            if filename == "" {
                alertTitle = "The download wasn't sucessful"
                alertMessage = "The download did not suggest a filename, so something is wrong here. This should not happen."
                Self.logger.error("The download did not suggest a filename, so something is wrong here. This should not happen.")

                alertShown = true
                return
            }
            guard let localURL = localURL else {
                print("no local url")
                Self.logger.error("no local url in transitionDownload")
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
                runningTask = Task {
                    await tellServerDownloadWasSuccessful()
                    runningTask = nil
                }
            } catch {
                print("Error in transitionDownload: \(error)")
                Self.logger.error("Error in transitionDownload: \(error)")
            }
        }
        observation = downloadTask!.progress.observe(\.fractionCompleted) { observationProgress, _ in
            DispatchQueue.main.async {
                taskProgress = observationProgress.fractionCompleted
            }
        }
        downloadTask!.resume()
    }
    
    func tellServerDownloadWasSuccessful() async {
        Self.logger.notice("tellServerDownloadWasSuccessful")
        guard $app_state.api_state.wrappedValue >= .connected, app_state.api_token != "" else {
            alertTitle = "Error in tellServerDownloadWasSuccessful"
            alertMessage = "This should not have happened at all!"
            alertShown = true
            return
        }
        
        let route = api_workstation_download_finished.replacingOccurrences(of: "<dock-id>", with: app_state.settings.dock_id)
        let url_str = "\(app_state.settings.server_url)\(route)"
        guard let url = URL(string: url_str) else {
            alertTitle = "Error in tellServerDownloadWasSuccessful"
            alertMessage = "Cannot build URL. This should not have happened."
            alertShown = true
            return
        }
        
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
        
        do {
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                alertTitle = "Error in tellServerDownloadWasSuccessful"
                alertMessage = "Error informing Server about a successful download: \(httpResponse.statusCode)"
                alertShown = true
                return
            } else {
                guard let response = try? JSONDecoder().decode(ApiDownloadWorkstationFinsishedResponse.self, from: data) else {
                        throw(APIError.runtimeError("Cannot decode response"))
                    }

                if response.success {
                    DispatchQueue.main.async {
                        Self.logger.notice("Download successfully declared.")
                        app_state.state = .downloaded
                        app_state.save()
                        Self.logger.notice("app_state changed to .downloaded")
                    }
                } else {
                    alertTitle = "Error in tellServerDownloadWasSuccessful"
                    alertMessage = "The server did not acknowledge the download. That's pretty strange and should not have happened."
                    alertShown = true
                }
            }
        } catch {
            Self.logger.error("Error in tellServerDownloadWasSuccessful: \(error, privacy: .public)")
            app_state.setApiState(api_state: .error)
        }
    }
    
    func transitionUpload() {
        Self.logger.notice("transitionUpload: transitionUpload starts")
        alertTitle = ""
        do {
            let urlFMP12 = getDocumentUrl()
            Self.logger.notice("transitionUpload: urlFMP12 fetched")
            if urlFMP12 == nil {
                alertTitle = "no database in stock"
                alertMessage = "Sorry, for some reason there is not database that could be sent. That should not happen."
                Self.logger.error("Error in transitionUpload: \(alertTitle, privacy: .public)")
                throw AnError.runtimeError(alertTitle)
            }
            guard $app_state.api_state.wrappedValue == .docked, app_state.api_token != "", (app_state.state == .needs_upload || app_state.state == .is_uploaded) else {
                alertTitle = "Kiosk not ready for upload"
                Self.logger.error("Error in transitionUpload: \(alertTitle, privacy: .public)")
                alertMessage = "Either the connection is missing or the dock is not ready for an upload."
                throw AnError.runtimeError(alertTitle)
            }
            Self.logger.notice("transitionUpload: Cancelling upload task")
            uploadTask?.cancel()
            uploadTask = nil
            Self.logger.notice("transitionUpload: Invalidating observation")
            observation?.invalidate()
            taskProgress = 0
            let route = api_workstation_upload.replacingOccurrences(of: "<dock-id>", with: app_state.settings.dock_id)
            Self.logger.notice("transitionUpload: api_workstation_upload.replacingOccurrences done.")
            let url_str = "\(app_state.settings.server_url)\(route)"
            guard let url = URL(string: url_str) else {
                alertTitle = "Internal Error"
                alertMessage = "I don't know where to send anything. That should not happen."
                Self.logger.error("Error in transitionUpload: \(alertMessage, privacy: .public)")
                throw(APIError.runtimeError(alertTitle))
            }
            
            Self.logger.error("transitionUpload: uploading to \(url.absoluteString, privacy: .public)")
            
            startUploadRequest(url: url, urlFMP12: urlFMP12!)

        } catch {
            Self.logger.error("Exception B in transitionUpload: \(error, privacy: .public)")
            if alertTitle != "" {
                alertShown = true
            }
            app_state.transitioning = false
        }
    }
    
    func startUploadRequest(url: URL, urlFMP12: URL) {
        let queue = DispatchQueue(label: "com.kioskbridge.upload_queue")
        let filename = url.lastPathComponent
        refreshMemoryUsage()
        queue.async {
            do {
                // var request: URLRequest
                let mimeType="application/octet-stream"
                let named="file"
                let boundary: String = UUID().uuidString
                // let mpfRequest = MultipartFormDataRequest(url: url)
                Self.logger.notice("transitionUpload: creating fileData")
                var fileData: Data? = try Data(contentsOf: urlFMP12)
                Self.logger.notice("transitionUpload: creating mpfRequest")
                let httpBody = NSMutableData()
                httpBody.append("--\(boundary)\r\n")
                httpBody.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
                httpBody.append("Content-Type: \(mimeType)\r\n")
                httpBody.append("\r\n")
                httpBody.append(fileData!)
                httpBody.append("\r\n")
                httpBody.append("--\(boundary)--")

                // mpfRequest.addFileField(named: "file", filename: url.lastPathComponent, data: &fileData!)
                fileData?.removeAll()
                fileData = nil
                // request = mpfRequest.asURLRequest()

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

                request.httpBody = httpBody as Data
                Self.logger.notice("transitionUpload: adding Bearer Headers")
                request.setValue(
                    "Bearer <<access-token>>",
                    forHTTPHeaderField: "Authentication"
                )

                DispatchQueue.main.async {

                    refreshMemoryUsage()
                    startUploadTask(request: &request)
                }
            } catch {
                Self.logger.error("Error in startUploadRequest: \(error.localizedDescription)")
            }
        }
    }
    
    func startUploadTask(request: inout URLRequest) {
        let sessionConfiguration = URLSessionConfiguration.default
        
        sessionConfiguration.httpAdditionalHeaders = [
            "Authorization": "Bearer \(app_state.api_token)",
            "X-CSRFToken": app_state.csrf_token
        ]
        Self.logger.notice("transitionUpload: creating session")
        let session = URLSession(configuration: sessionConfiguration)

        Self.logger.notice("transitionUpload: creating uploadTask")
        uploadTask = session.dataTask(
                    with: request,
                    completionHandler: { data, response, error in
                        // Validate response and call handler
                        app_state.transitioning = false

                        observation?.invalidate()
                        uploadTask?.cancel()
                        uploadTask = nil
                        if let error = error {
                            alertTitle = "Upload failed"
                            alertMessage = "The upload of the file failed due to a network error."
                            Self.logger.error("Error in transitionUpload: \(alertMessage, privacy: .public)")

                            if let httpResponse = response as? HTTPURLResponse {
                                alertMessage += " (\(String(httpResponse.statusCode))"
                            } else {
                                alertMessage += " \(error)"
                            }
                            alertShown = true
                            return
                        }
                        guard let response = response else {
                            alertTitle = "The upload wasn't sucessful"
                            alertMessage = "The upload did not come back with a urlResponse. Something is wrong here. This should not happen."
                            Self.logger.error("Error in transitionUpload: \(alertMessage, privacy: .public)")
                            alertShown = true
                            return
                        }
                        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                            alertTitle = "The upload wasn't sucessful"
                            alertMessage = "The server did not accept the file (http error code \(httpResponse.statusCode)."
                            Self.logger.error("Error in transitionUpload: \(alertMessage, privacy: .public)")
                            alertShown = true
                            return
                        }
                        if let data = data {
                            do {
                                let result:ApiUploadResponse = try JSONDecoder().decode(ApiUploadResponse.self, from: data)
                                if !result.success {
                                    alertTitle = "Kiosk did not accept the upload"
                                    alertMessage = result.message
                                    Self.logger.error("Error in transitionUpload: Kiosk did not accept the upload: \(alertMessage, privacy: .public)")

                                    alertShown = true
                                    return
                                } else {
                                    DispatchQueue.main.async {
                                        refreshMemoryUsage()
                                        Self.logger.error("transitionUpload: Upload successful")
                                        app_state.state = .is_uploaded
                                        app_state.save()
                                        Self.logger.error("transitionUpload: app_state changed to .is_uploaded")
                                    }
                                }
                            } catch {
                                Self.logger.error("Exception A in transitionUpload: \(error, privacy: .public)")
                            }
                        }
                    }
                )
        observation = uploadTask!.progress.observe(\.fractionCompleted) { observationProgress, _ in
            DispatchQueue.main.async {
                taskProgress = observationProgress.fractionCompleted
            }
        }

        uploadTask!.resume()

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
                if !docPath.isDirectory {
                    return docPath
                }
            }
        } catch {
            Self.logger.error("Error in getDocumentURL: \(error, privacy: .public)")
        }
        return nil
    }
    
    func clearAllDocuments(InBox: Bool = false) throws {
        Self.logger.error("clearAllDocuments starts")

        let fm = FileManager.default
        var documentsUrl = try FileManager.default.url(
            for: .documentDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: false)

        if InBox {
            documentsUrl.appendPathComponent("Inbox")
        }

        let documents = try fm.contentsOfDirectory(atPath: documentsUrl.path)
        for doc in documents {
            let docPath = documentsUrl.appendingPathComponent(doc)
            if (!docPath.isDirectory) {
                print("Deleting file \(docPath)")
                try fm.removeItem(at: docPath)
            }
        }
        Self.logger.error("clearAllDocuments ends")
    }
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
                               context: UIViewControllerRepresentableContext<ActivityView>) {
       print("updateUIViewController")
   }

}


struct SettingsDisplayView: View {
    @ObservedObject var settings: KioskBridgeSettings
    @Binding var settings_shown: Bool
    
    var body: some View {
        HStack {
            Label("\(settings.user_id)", systemImage: settings.user_image)
//                .padding(.all)
            Spacer()
            Label("\(settings.dock_id)", systemImage: settings.dock_image)
                .padding(.horizontal)
            Spacer()
            Button() {
                settings_shown = true
            }
            label: {
                Label("settings", systemImage: "gearshape.fill")
            }
            .padding(.trailing)
            .background(settings.unsafe_mode ? Color(red:0.7, green: 0,blue: 0) : Color.clear)
            .foregroundColor(settings.unsafe_mode ? Color(red:1, green: 1,blue: 0) : Color.black)
        }
        
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        @State var openedUrl: URL? = nil
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
        return KioskBridgeView(app_state: app_state, openedUrl: $openedUrl)
    }
}
