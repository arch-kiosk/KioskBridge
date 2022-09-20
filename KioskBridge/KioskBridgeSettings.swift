//
//  KioskBridgeSettings.swift
//  KioskBridge
//
//  Created by Lutz Klein on 8/21/22.
//

import Foundation



class KioskBridgeSettings: ObservableObject, Codable {
    enum CodingKeys: CodingKey {
        case server_url, user_id, dock_id, password
    }

    @Published var server_url: String = ""
    @Published var user_id: String = ""
    @Published var dock_id: String = ""
    @Published var password: String = ""
    
    init() {
        server_url = ""
    }
    
    func save() {
        print("saving...")
        if let encoded = try? JSONEncoder().encode(self) {
            print(encoded)
            UserDefaults.standard.set(encoded, forKey: "KioskBridgeSettings")
        }
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        server_url = try container.decode(String.self, forKey: .server_url)
        user_id = try container.decode(String.self, forKey: .user_id)
        dock_id = try container.decode(String.self, forKey: .dock_id)
        password = try container.decode(String.self, forKey: .password)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(server_url, forKey: .server_url)
        try container.encode(user_id, forKey: .user_id)
        try container.encode(password, forKey: .password)
        try container.encode(dock_id, forKey: .dock_id)
    }

    var user_image: String {
        get {
            user_id.isEmpty ? "person.fill.questionmark" : "person.circle.fill"
        }
    }
    var dock_image: String {
        get {
            dock_id.isEmpty ? "questionmark.square.dashed" : "ipad"
        }
    }
    
}
