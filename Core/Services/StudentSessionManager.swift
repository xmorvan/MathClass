//
//  StudentSessionManager.swift
//  MathClass
//
//  Created on 04.09.2025.
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

/// Manages student sessions via class code + name selection.
/// Students authenticate by entering a class code (MX-XXXX) and selecting their name.
/// The session is persisted in the Keychain so the student doesn't need to re-enter it.
@MainActor
final class StudentSessionManager: ObservableObject {
    static let shared = StudentSessionManager()

    /// Coarse-grained restoration state for ContentView gating (ISSUE-007).
    /// `loading` covers cold-start until the Keychain → Firestore lookup
    /// finishes; the UI must wait on this before deciding what to render.
    enum SessionState {
        case loading
        case signedIn
        case signedOut
    }

    @Published private(set) var sessionState: SessionState = .loading
    @Published private(set) var currentStudent: Student?
    @Published private(set) var currentClassID: String?
    @Published private(set) var isLoggedIn: Bool = false
    @Published var loginError: String?

    // Keychain keys
    private let studentIDKey = "studentSessionID"
    private let classIDKey = "studentClassID"
    private let deviceTokenKey = "deviceToken"

    /// Unique device identifier for this iPad.
    private(set) lazy var deviceToken: String = {
        if let existingToken = KeychainHelper.shared.read(key: deviceTokenKey)?.toString() {
            return existingToken
        }
        let newToken = UUID().uuidString
        _ = KeychainHelper.shared.save(key: deviceTokenKey, data: Data(newToken.utf8))
        return newToken
    }()

    private init() {
        tryRestoreSession()
    }

    // MARK: - Class Code Lookup

    /// Look up a class by its MX-XXXX code.
    /// Returns the ClassRoom if found, nil otherwise.
    func lookupClass(code: String) async throws -> ClassRoom? {
        let normalizedCode = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return try await DataService.shared.classRepository.getClass(byCode: normalizedCode)
    }

    /// Get the list of students in a class (for the name selection screen).
    func getStudents(classID: String) async throws -> [Student] {
        try await DataService.shared.studentRepository.getStudents(classID: classID)
    }

    // MARK: - Login

    /// Log in as a student by selecting their name from the class.
    func login(student: Student, classID: String) async {
        // Save session to Keychain
        guard let studentID = student.id else {
            await setError("Erreur: identifiant élève invalide.")
            return
        }

        _ = KeychainHelper.shared.save(key: studentIDKey, data: Data(studentID.utf8))
        _ = KeychainHelper.shared.save(key: classIDKey, data: Data(classID.utf8))

        // Bind the iPad's anonymous Firebase identity to this student so all
        // subsequent Firestore/Storage/callable requests carry an
        // `auth.token.studentID` claim. The rules and Cloud Functions rely on
        // that claim for ownership checks (ISSUE-014). Failure here is fatal
        // for the session — without the claim, the student cannot read their
        // own submissions or upload PNGs.
        do {
            try await self.linkSession(studentID: studentID, classID: classID)
        } catch {
            await setError("Erreur d'authentification: \(error.localizedDescription)")
            _ = KeychainHelper.shared.delete(key: studentIDKey)
            _ = KeychainHelper.shared.delete(key: classIDKey)
            return
        }

        // Class is @MainActor, so direct mutation is safe (and any await
        // suspension above resumes on the MainActor automatically).
        self.currentStudent = student
        self.currentClassID = classID
        self.isLoggedIn = true
        self.sessionState = .signedIn
        self.loginError = nil

        // Set student role on AuthenticationService
        AuthenticationService.shared.setStudentRole()
    }

    // MARK: - Logout

    func logout() {
        // Clear Keychain
        _ = KeychainHelper.shared.delete(key: studentIDKey)
        _ = KeychainHelper.shared.delete(key: classIDKey)

        // Sign out of the anonymous Firebase identity so a different student
        // can claim the iPad without inheriting the previous student's
        // `auth.token.studentID` claim. Firebase Auth state changes are
        // observed by AuthenticationService, which clears userRole.
        do {
            if let user = Auth.auth().currentUser, user.isAnonymous {
                try Auth.auth().signOut()
            }
        } catch {
            print("Erreur déconnexion Firebase Auth (\((error as NSError).code))")
        }

        // Reset state
        currentStudent = nil
        currentClassID = nil
        isLoggedIn = false
        sessionState = .signedOut
        loginError = nil

        // Clear student role
        AuthenticationService.shared.clearStudentRole()

        // Notify UI
        NotificationCenter.default.post(
            name: Notification.Name("StudentLogout"),
            object: nil
        )
    }

    // MARK: - Session Restoration

    private func tryRestoreSession() {
        guard let studentIDData = KeychainHelper.shared.read(key: studentIDKey),
              let classIDData = KeychainHelper.shared.read(key: classIDKey),
              let studentID = String(data: studentIDData, encoding: .utf8),
              let classID = String(data: classIDData, encoding: .utf8) else {
            // No persisted session: leave loading and immediately settle.
            self.sessionState = .signedOut
            return
        }

        // Stay in `.loading` while the Firestore round-trip resolves so the
        // UI doesn't flash a "signed out" screen on cold start (ISSUE-007).
        Task { [weak self] in
            guard let self else { return }
            do {
                // Re-establish the auth claim before the Firestore read —
                // anonymous users persist across launches, but the custom
                // claim must be reattached when the deviceToken on the
                // Student doc has been rotated (or when we reinstalled).
                try await self.linkSession(studentID: studentID, classID: classID)

                let student: Student = try await FirebaseService.shared.getDocument(
                    studentID,
                    from: "classes/\(classID)/students"
                )

                // Inherits MainActor from the enclosing class, no explicit hop needed.
                self.currentStudent = student
                self.currentClassID = classID
                self.isLoggedIn = true
                self.sessionState = .signedIn

                AuthenticationService.shared.setStudentRole()
            } catch {
                // Invalid session — clear it and settle to signed-out.
                _ = KeychainHelper.shared.delete(key: studentIDKey)
                _ = KeychainHelper.shared.delete(key: classIDKey)
                self.sessionState = .signedOut
            }
        }
    }

    // MARK: - Anonymous-auth + linkStudentSession

    /// Sign in anonymously (if not already), call the `link_student_session`
    /// Cloud Function to attach `studentID` / `classID` / `role` claims to
    /// this UID, and force an ID-token refresh so the new claims propagate
    /// to subsequent Firestore / Storage / callable requests.
    ///
    /// Idempotent: subsequent calls for the same student/device validate the
    /// existing deviceToken on the Student doc; the first call binds it
    /// (trust-on-first-use). Mismatched deviceTokens are rejected by the
    /// function — the teacher must reset the deviceToken on the Student doc
    /// before a different device can claim that identity.
    private func linkSession(studentID: String, classID: String) async throws {
        let auth = Auth.auth()
        if auth.currentUser == nil {
            _ = try await auth.signInAnonymously()
        }

        let functions = Functions.functions(region: "europe-west6")
        let callable = functions.httpsCallable("link_student_session")
        callable.timeoutInterval = 20
        _ = try await callable.call([
            "classID": classID,
            "studentID": studentID,
            "deviceToken": deviceToken,
        ])

        // Pull a fresh ID token so the next Firestore / callable request
        // carries the new claim. Without this, claims set by the function
        // only become visible on the next "natural" refresh (~1h).
        _ = try await auth.currentUser?.getIDTokenResult(forcingRefresh: true)
    }

    // MARK: - Helpers

    private func setError(_ message: String) async {
        // Class is @MainActor, so the assignment is already on main.
        self.loginError = message
    }
}

// MARK: - Data Extension

extension Data {
    func toString() -> String? {
        return String(data: self, encoding: .utf8)
    }
}
