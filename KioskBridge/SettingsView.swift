//
//  settings.swift
//  KioskBridge
//
//  Created by Lutz Klein on 8/21/22.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: KioskBridgeSettings
    @State var formerDockId = ""
    @State var askForReset = false
    @State var askForDockChange = false
    @ObservedObject var appState: AppState
    
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
                    VStack {
                        Button("reset app state")  {
                            askForReset = true
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundColor(Color("redish"))
                        .padding()
   }
                }
                    
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
    func saveAndDismiss() {
        settings.save()
        appState.save()
        dismiss()
    }
}

struct settings_Previews: PreviewProvider {
    static var previews: some View {
        let settings = KioskBridgeSettings()
        let app_state = AppState()
        settings.server_url = "192.168.1.12"
        settings.user_id = "Lutz"
        settings.dock_id = "Lutz's X1"
        return SettingsView(settings: settings, appState: app_state)
    }
}
