//
//  GSMTowerWatchApp.swift
//  GSMTowerWatch Watch App
//
//  Created by Jakub Szczepaniak on 01/07/2025.
//

import SwiftUI

@main
struct GSMTowerWatch_Watch_AppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView().onAppear(){
                _ = WatchSessionManager.shared // Ensure the session manager is initialized
            }
        }
    }
}
