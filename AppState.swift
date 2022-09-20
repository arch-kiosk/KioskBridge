//
//  AppState.swift
//  KioskBridge
//
//  Created by Lutz Klein on 9/1/22.
//

import Foundation

enum PersistedBridgeState:Int, Codable {
    case idle, downloaded, sent_to_filemaker, needs_upload
}

class AppState: ObservableObject, Codable {
    enum CodingKeys: CodingKey {
        case state
    }
    
    enum DockStates {case not_ready, prepared_for_download, uploaded}
    @Published var dock_state: DockStates = .not_ready
    
    @Published var api_state: ApiStatus = .disconnected
    @Published var api_token: String = ""
    
    //    enum AppStates {case idle, downloaded, needs_upload}
    //    @Published var app_state: AppStates = .idle
    @Published var settings: KioskBridgeSettings = KioskBridgeSettings()
    @Published var state: PersistedBridgeState = .idle
    
    @Published var app_state_message: String = ""
    @Published var transitions: [String] = []
    @Published var app_error_state: String = ""
    var debug = false
    
    init() {
        load()
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = PersistedBridgeState(rawValue: try container.decode(Int.self, forKey: .state))!
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
    }
    
    func save() {
        process_app_state()
        print("saving app_state...")
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: "KioskBridgeAppState")
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
        case "uploaded": self.dock_state = .uploaded
        default: dock_state = .not_ready
        }
        process_app_state()
    }
    
    func process_app_state() {
        app_error_state = ""
        print("reprocessed AppState")
        var new_transitions: [String] = []
        switch (state) {
        case .idle:
            if (api_state >= .docked) {
                if (dock_state == .prepared_for_download) {
                    new_transitions = ["download from Kiosk"]
                } else {
                    app_error_state = "Dock not ready for download"
                }
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
            }
        }
        print("changing transitions")
        transitions = new_transitions
    }
    
    func get_transitions() -> [String] {
        return transitions
    }
    
    func get_state_text()->String {
        switch (state) {
            
        case .idle:
            return "idle"
        case .downloaded:
            return "downloaded"
        case .needs_upload:
            return "needs_upload"
        case .sent_to_filemaker:
            return "sent_to_filemaker"
        }
    }
}
