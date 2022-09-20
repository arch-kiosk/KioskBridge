//
//  KioskApi.swift
//  KioskBridge
//
//  Created by Lutz Klein on 8/30/22.
//

import SwiftUI

enum ApiStatus: Comparable {
    case disconnected, connecting, unauthorized, error, connected, nodock, wrongdocktype, docked
}

let api_login_path = "/api/v1/login"

struct ApiLogin: Codable {
    var userid: String
    var password: String
}


struct ApiLoginResponse: Codable {
    var token: String
}




struct ApiDock: Codable {
    var dock_id: String
}

let api_dock_path = "/api/syncmanager/v1/dock"

struct ApiDockResponse: Codable {
    var description: String
    var icon_code: String
    var type: String
    var state_description: String
    var workstation_class: String
    var state_text: String
    var id: String
}

let api_workstation_download = "/kioskfilemakerworkstation/workstation/<dock-id>/download/start"
