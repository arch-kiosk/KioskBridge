//
//  AppDelegate.swift
//  KioskBridge
//
//  Created by Lutz Klein on 9/23/22.
//
// NOT IN USE!

import Foundation
import UIKit

class MyAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, open url: URL, sourceApplication: String?, annotation: Any) -> Bool {
        print("application opened with \(url.absoluteString)")
        return true
    }
    
    
    func applicationDidFinishLaunching(_ application: UIApplication) {
        print("The application became active!")
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        print("The application became active!")
    }
}
