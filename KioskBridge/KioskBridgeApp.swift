import SwiftUI

@main
struct KioskBridgeApp: App {
    @State var openedUrl: URL? = nil
    
    var body: some Scene {
        WindowGroup {
            KioskBridgeView(openedUrl: $openedUrl)
                .onOpenURL { url in
                    // Simply assign it. No security scope leaks or premature closures.
                    openedUrl = url
                }
        }
    }
}