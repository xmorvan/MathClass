//
//  MathClassApp.swift
//  MathClass
//
//  Created by Xavier Morvan on 23.01.2025.
//

import SwiftUI
import FirebaseCore
import FirebaseFirestore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()

        // Enable Firebase offline persistence
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings(
            sizeBytes: NSNumber(value: Int64(FirestoreCacheSizeUnlimited))
        )
        Firestore.firestore().settings = FirebaseEmulator.configureIfEnabled(settings)

        return true
    }
}

@main
struct MathClassApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
