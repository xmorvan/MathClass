//
//  FirebaseEmulator.swift
//  MathClass
//
//  Routes Auth, Firestore, Storage and Functions to the local Firebase
//  emulator suite (`firebase emulators:start`) when the app is launched with
//  the environment variable `USE_FIREBASE_EMULATOR=1`. Debug builds only, so
//  a release build can never talk to a local emulator by mistake.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage

enum FirebaseEmulator {
    /// True when this launch should use the local emulators.
    static var isEnabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["USE_FIREBASE_EMULATOR"] == "1"
        #else
        return false
        #endif
    }

    /// Call right after `FirebaseApp.configure()` and before any other
    /// Firebase access. Returns the Firestore settings to apply.
    static func configureIfEnabled(_ settings: FirestoreSettings) -> FirestoreSettings {
        guard isEnabled else { return settings }
        let host: String = ProcessInfo.processInfo.environment["FIREBASE_EMULATOR_HOST"] ?? "127.0.0.1"

        Auth.auth().useEmulator(withHost: host, port: 9099)
        Storage.storage().useEmulator(withHost: host, port: 9199)
        Functions.functions(region: "europe-west6").useEmulator(withHost: host, port: 5001)

        settings.host = "\(host):8080"
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        print("🔧 Firebase emulators enabled on \(host)")
        return settings
    }
}
