//
//  KioskBridgeApp.swift
//  KioskBridge
//
//  Created by Lutz Klein on 8/20/22.
//

import SwiftUI

@main
struct KioskBridgeApp: App {
    @State var openedUrl: URL? = nil
    var body: some Scene {
        WindowGroup {
            KioskBridgeView(openedUrl: $openedUrl)
                .onOpenURL { url in
                    openedUrl = url
                        }
        }
    }
}
