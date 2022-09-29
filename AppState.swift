//
//  AppState.swift
//  KioskBridge
//
//  Created by Lutz Klein on 9/1/22.
//

import Foundation

enum PersistedBridgeState:Int, Codable {
    case idle, downloaded, sent_to_filemaker, needs_upload, is_uploaded
}

class AppState: ObservableObject, Codable {
    enum CodingKeys: CodingKey {
        case state, sentFileName
    }
    
    enum DockStates {case unknown, not_ready, prepared_for_download, uploaded}
    @Published var dock_state: DockStates = .unknown
    
    @Published var api_state: ApiStatus = .disconnected
    @Published var api_token: String = ""
    
    //    enum AppStates {case idle, downloaded, needs_upload}
    //    @Published var app_state: AppStates = .idle
    @Published var settings: KioskBridgeSettings = KioskBridgeSettings()
    @Published var state: PersistedBridgeState = .idle
    @Published var sentFileName: String = ""
    
    @Published var app_state_message: String = ""
    @Published var transitions: [String] = []
    @Published var app_error_state: String = ""
    @Published var app_error_is_warning: Bool = false
    
    var debug = false
    
    init() {
        load()
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = PersistedBridgeState(rawValue: try container.decode(Int.self, forKey: .state))!
        sentFileName = try container.decode(String.self, forKey: .sentFileName)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encode(sentFileName, forKey: .sentFileName)
    }
    
    func save() {
        process_app_state()
        print("saving app_state...")
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: "KioskBridgeAppState")
            print("App_state saved")
        } else {
            print("Error decoding!")
        }
        
    }
    
    func load() {
        print("Loading settings")
        self.settings = KioskBridgeSettings()
        if let savedData = UserDefaults.standard.data(forKey: "KioskBridgeSettings") {
            if let decodedData = try? JSONDecoder().decode(KioskBridgeSettings.self, from: savedData) {
                self.settings = decodedData
            }
        }
        self.state = .idle
        if let savedData = UserDefaults.standard.data(forKey: "KioskBridgeAppState") {
            if let decodedState = try? JSONDecoder().decode(AppState.self, from: savedData) {
                self.state = decodedState.state
                self.sentFileName = decodedState.sentFileName
            }
        }
    }
    
    func setApiState(api_state: ApiStatus) {
        self.api_state = api_state
        process_app_state()
    }
    
    func setDockStateFromStr(dock_state_str: String) {
        switch (dock_state_str) {
        case "prepared for download", "in the field": self.dock_state = .prepared_for_download
        case "uploaded - needs import": self.dock_state = .uploaded
        default: dock_state = .not_ready
        }
        process_app_state()
    }
    
    func process_app_state() {
        app_error_state = ""
        print("reprocessed AppState")
        var new_transitions: [String] = []
        app_error_is_warning = false
        switch (state) {
        case .idle:
            if (api_state >= .docked) {
                if (dock_state == .prepared_for_download) {
                    new_transitions = ["download from Kiosk"]
                } else {
                    app_error_state = "Dock not prepared for download, yet"
                    app_error_is_warning = true
                }
            } else {
                new_transitions.append("please connect to the Kiosk network for the next step (and then hit this button)")
            }
        case .downloaded:
            new_transitions = ["send to filemaker"]
            if (api_state >= .docked) {
                new_transitions.append("download from Kiosk again")
            }
        case .sent_to_filemaker:
            new_transitions = ["send to filemaker again"]
            if (api_state >= .docked) {
                new_transitions.append("download from Kiosk again")
            }
        case .needs_upload:
            if (api_state >= .docked) {
                new_transitions.append("upload to Kiosk")
            } else {
                new_transitions.append("please connect to the Kiosk network for the next step (and then hit this button)")
            }
        case .is_uploaded:
            if (api_state >= .docked) {
                if (dock_state == .uploaded) {
                    new_transitions.append("upload to Kiosk again")
                }   
            }
            else {
                new_transitions.append("please connect to the Kiosk network for the next step (and then hit this button)")
            }
        }
        transitions = new_transitions
    }
    
    func get_transitions() -> [String] {
        return transitions
    }
    
    func get_state_text()->String {
        switch (state) {
            
        case .idle:
            if dock_state == .prepared_for_download {
                return "ready for download"
            } else {
                return "idle: Waiting for the dock to be prepared for download"
            }
        case .downloaded:
            return "downloaded: Ready to send the file to FileMaker"
        case .sent_to_filemaker:
            return "waiting to receive a database from FileMaker"
        case .needs_upload:
            return "ready to upload the database back to Kiosk"
        case .is_uploaded:
            return "waiting for the uploaded data to be imported in Kiosk"
        }
    }
}
