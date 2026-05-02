//
//  MathClass_macOSApp.swift
//  MathClass-macOS
//
//  Created by Xavier Morvan on 23.01.2025.
//

import SwiftUI
import FirebaseCore
import FirebaseFirestore

@main
struct MathClass_macOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        FirebaseApp.configure()

        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings(
            sizeBytes: NSNumber(value: FirestoreCacheSizeUnlimited)
        )
        Firestore.firestore().settings = settings
    }

    var body: some Scene {
        WindowGroup {
            ContentView_macOS()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // macOS app launched
    }
}
