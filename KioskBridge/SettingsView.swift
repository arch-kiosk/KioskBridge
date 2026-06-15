//
//  settings.swift
//  KioskBridge
//
//  Created by Lutz Klein on 8/21/22.
//

import SwiftUI
import OSLog
import Foundation

@MainActor final class LogStore: ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: LogStore.self)
    )

    var logFilename: URL?
    
    public func getFileName() -> URL? {
        let filenameAsString = logFilename?.absoluteString
        print("log file: ", filenameAsString ?? "")
      return logFilename
    }
    
    func export() {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(timeIntervalSinceLatestBoot: 1)
            let entries = try store
                .getEntries(at: position)
                .compactMap { $0 as? OSLogEntryLog }
                .filter { $0.subsystem == Bundle.main.bundleIdentifier! }
                .map { "[\($0.date.formatted())] [\($0.category)] \($0.composedMessage)" }
            let textData = entries.joined(separator: "\n")
            let filename = FileManager.default.urls(for: .documentDirectory,
                                                in: .userDomainMask)[0].appendingPathComponent("kioskbridgelog.txt")
            let filenameAsString = filename.absoluteString
            print("log file: ", filenameAsString)
            print("Writing log to file name \(filenameAsString)")
            do {
                try textData.write(to: filename, atomically: true, encoding: String.Encoding.utf8)
                logFilename = filename
            } catch {
                // failed to write file – bad permissions, bad filename, missing permissions, or more likely it can't be converted to the encoding
                print("Error writing log lines to \(filename)")
            }
        } catch {
            print("Error")
            Self.logger.warning("\(error.localizedDescription, privacy: .public)")
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: KioskBridgeSettings
    @State var formerDockId = ""
    @State var askForReset = false
    @State var askForDockChange = false
    @State var wrongDockId = false
    @ObservedObject var appState: AppState
    @ObservedObject var logs: LogStore
    @State var showLogButton = true
    @State private var exportShown = false
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                VStack {
                    VStack(alignment: .leading){
                        Text("Kiosk URL")
                            .font(Font.caption)
                        TextField("Kiosk URL", text: $settings.server_url,
                                  prompt: Text("Please enter a valid ip address"))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    }
                    VStack(alignment: .leading){
                        Text("User Id")
                            .font(Font.caption)
                        TextField("User Id", text: $settings.user_id,
                                  prompt: Text("Please enter a valid Kiosk user id"))
                        .textInputAutocapitalization(.never)
                    }
                    VStack(alignment: .leading){
                        Text("Password")
                            .font(Font.caption)
                        SecureField("Password", text: $settings.password,
                                    prompt: Text("Please enter the Kiosk user's password"))
                        .textInputAutocapitalization(.never)
                    }
                    VStack(alignment: .leading){
                        Text("Dock Id")
                            .font(Font.caption)
                        TextField("Dock Id", text: $settings.dock_id,
                                  prompt: Text("Please enter the id of the dock you want to connect to"))
                        .textInputAutocapitalization(.never)
                    }
                    Spacer()
                    VStack(alignment: .leading){
                        Toggle(isOn: $settings.unsafe_mode) {
                            Text("unsafe mode").frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    Spacer()
                    Spacer()
                    HStack(alignment: .top) {
                        Button("reset app state")  {
                            askForReset = true
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        //.frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundColor(Color("redish"))
                        //.padding()
                        
                        
                           // and if you want to be explicit / future-proof...
                           // .progressViewStyle(CircularProgressViewStyle())
                        if (showLogButton && !exportShown) {
                            
                            Button("get 24h log") {
                                showLogButton = false
                                startExportLog()
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .foregroundColor(Color("redish"))
                        } else {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .foregroundColor(Color("redish"))
                        }
                        //.padding()
                    }
                }.disableAutocorrection(true)
            }
            .alert("Do you really want to connect to a different dock? KioskBridge will reset in this case.", isPresented: $askForDockChange) {
                Button("Yes") {
                    appState.state = .idle
                    saveAndDismiss()}
                Button("No") {
                    settings.dock_id = formerDockId
                    saveAndDismiss()
                }
            }
            .alert("Do you really want to reset the KioskBridge's current state?", isPresented: $askForReset) {
                Button("Yes") {
                    appState.state = .idle
                    saveAndDismiss()}
                Button("No") {
                    //Not doing anything
                }
            }
            .alert(isPresented: $wrongDockId) {
                        Alert(title: Text("Invalid Dock-Id "),
                              message: Text("There is a space in the dock id. Spaces and other special characters are not supported right now."),
                              dismissButton: .default(Text("Got it!")))
            }
            .sheet(isPresented: $exportShown) {
                ShareView(filename: logs.getFileName() ?? URL(fileURLWithPath: ""))
                            }

            
            .onChange(of: settings.dock_id) { [dock_id = settings.dock_id] newValue in
                if (formerDockId == "") {
                    formerDockId = dock_id
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: ToolbarItemPlacement.navigationBarLeading) {
                    Button("cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: ToolbarItemPlacement.navigationBarTrailing){
                    Button("save") {
                        if (formerDockId == "") {
                            saveAndDismiss()
                        } else {
                            askForDockChange = true
                        }
                    }
                }
            }
        }
    }
    
    func startExportLog() {
        let log_queue = DispatchQueue(label: "com.kioskbridge.log_queue")
        if (!exportShown) {
            log_queue.async {
                logs.export()
                DispatchQueue.main.async {
                    exportShown = true
                    showLogButton = true
                }
            }
        }
    }
    
    func saveAndDismiss() {
        if settings.dock_id.contains(" ") {
          wrongDockId = true
            return
        }
        settings.save()
        appState.save()
        dismiss()
    }

}

struct ShareView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIActivityViewController

    let filename: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [filename], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}

struct settings_Previews: PreviewProvider {
    static var previews: some View {
        let settings = KioskBridgeSettings()
        let app_state = AppState()
        settings.server_url = "192.168.1.12"
        settings.user_id = "Lutz"
        settings.dock_id = "Lutz's X1"
        return SettingsView(settings: settings, appState: app_state, logs: LogStore())
    }
}


