//
//  settings.swift
//  KioskBridge
//
//  Created by Lutz Klein on 8/21/22.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: KioskBridgeSettings
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
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
                    
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("save") {
                    settings.save()
                    dismiss()
                }
            }
        }
    }
}

struct settings_Previews: PreviewProvider {
    static var previews: some View {
        let settings = KioskBridgeSettings()
//        settings.server_url = "192.168.1.12"
//        settings.user_id = "Lutz"
//        settings.dock_id = "Lutz's X1"
        return SettingsView(settings: settings)
    }
}
