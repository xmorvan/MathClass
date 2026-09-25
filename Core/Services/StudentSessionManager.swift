//
//  StudentSessionManager.swift
//  MathClass
//
//  Created on 04.09.2025.
//

import SwiftUI
import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

/// A class found by its code, with the names to pick from.
struct JoinableClass {
    let classID: String
    let name: String
    let classCode: String
    /// Picker entries only: first name + last-name initial. The full
    /// student document is loaded once the seat is claimed.
    let students: [Student]
}

/// Manages student sessions via class code + name selection.
///
/// Students have no email account. The iPad signs in with an anonymous
/// Firebase account, and the `claim_student_seat` Cloud Function binds it to
/// one student by setting the custom claims {role, classID, studentID}. The
/// security rules only let that account read its own class and write its own
/// work. The session (studentID + classID + class code) is also kept in the
/// Keychain so the student doesn't need to re-enter it.
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
    private let classCodeKey = "studentClassCode"
    private let deviceTokenKey = "deviceToken"

    private let functions: Functions = Functions.functions(region: "europe-west6")

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

    /// Look up a class by its MX-XXXX code through the `join_class` Cloud
    /// Function. Returns nil when no class has this code.
    func joinClass(code: String) async throws -> JoinableClass? {
        let normalizedCode = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await AuthenticationService.shared.signInAnonymouslyIfNeeded()

        let response: [String: Any]
        do {
            let result = try await functions.httpsCallable("join_class")
                .call(["classCode": normalizedCode])
            guard let dict = result.data as? [String: Any] else { return nil }
            response = dict
        } catch let error as NSError where Self.isNotFound(error) {
            return nil
        }

        guard let classID = response["classID"] as? String else { return nil }
        let rawStudents = response["students"] as? [[String: Any]] ?? []
        let students: [Student] = rawStudents.compactMap { entry in
            guard let id = entry["id"] as? String else { return nil }
            let isLinked: Bool = entry["linked"] as? Bool ?? false
            return Student(
                id: id,
                firstName: entry["firstName"] as? String ?? "",
                lastName: entry["lastInitial"] as? String ?? "",
                classID: classID,
                // Only drives the "linked" badge in the picker.
                deviceToken: isLinked ? "linked" : nil
            )
        }
        return JoinableClass(
            classID: classID,
            name: response["className"] as? String ?? "",
            classCode: normalizedCode,
            students: students
        )
    }

    // MARK: - Login

    /// Log in as a student picked from the class list.
    func login(student: Student, joinedClass: JoinableClass) async {
        guard let studentID = student.id else {
            await setError("Erreur: identifiant élève invalide.")
            return
        }

        do {
            try await claimSeat(classCode: joinedClass.classCode, studentID: studentID)

            // The picker only had first name + initial; load the real doc,
            // which the new claims now allow.
            let fullStudent = try await DataService.shared.studentRepository
                .getStudent(id: studentID, classID: joinedClass.classID)

            _ = KeychainHelper.shared.save(key: studentIDKey, data: Data(studentID.utf8))
            _ = KeychainHelper.shared.save(key: classIDKey, data: Data(joinedClass.classID.utf8))
            _ = KeychainHelper.shared.save(key: classCodeKey, data: Data(joinedClass.classCode.utf8))

            // Link this iPad to the student (rules allow only this field).
            do {
                try await DataService.shared.studentRepository.updateDeviceToken(
                    deviceToken,
                    studentID: studentID,
                    classID: joinedClass.classID
                )
            } catch {
                print("Erreur mise à jour device token: \(error.localizedDescription)")
            }

            // Class is @MainActor, so direct mutation is safe (and any await
            // suspension above resumes on the MainActor automatically).
            self.currentStudent = fullStudent
            self.currentClassID = joinedClass.classID
            self.isLoggedIn = true
            self.sessionState = .signedIn
            self.loginError = nil

            AuthenticationService.shared.setStudentRole()
        } catch {
            await setError("Connexion impossible : \(error.localizedDescription)")
        }
    }

    /// Ask the server to bind this iPad's anonymous account to the student,
    /// then refresh the ID token so the new claims apply immediately.
    private func claimSeat(classCode: String, studentID: String) async throws {
        let user = try await AuthenticationService.shared.signInAnonymouslyIfNeeded()
        _ = try await functions.httpsCallable("claim_student_seat")
            .call(["classCode": classCode, "studentID": studentID])
        _ = try await user.getIDTokenResult(forcingRefresh: true)
    }

    // MARK: - Logout

    func logout() {
        // Clear Keychain
        _ = KeychainHelper.shared.delete(key: studentIDKey)
        _ = KeychainHelper.shared.delete(key: classIDKey)
        _ = KeychainHelper.shared.delete(key: classCodeKey)

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

        // Drop the anonymous account and the student role
        AuthenticationService.shared.signOutStudent()
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
        let classCode = KeychainHelper.shared.read(key: classCodeKey)?.toString()

        // Stay in `.loading` while the Firestore round-trip resolves so the
        // UI doesn't flash a "signed out" screen on cold start (ISSUE-007).
        Task { [weak self] in
            guard let self else { return }
            do {
                try await ensureClaims(studentID: studentID, classCode: classCode)

                let student: Student = try await DataService.shared.studentRepository
                    .getStudent(id: studentID, classID: classID)

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
                _ = KeychainHelper.shared.delete(key: classCodeKey)
                self.sessionState = .signedOut
            }
        }
    }

    /// Make sure the signed-in anonymous account carries the claims for
    /// `studentID`, re-claiming the seat when it doesn't (sessions saved
    /// before student accounts existed, or a signed-out account).
    private func ensureClaims(studentID: String, classCode: String?) async throws {
        if let user = Auth.auth().currentUser, user.isAnonymous {
            do {
                let token = try await user.getIDTokenResult()
                if token.claims["studentID"] as? String == studentID {
                    return
                }
            } catch {
                // Offline cold start: keep the saved session and let
                // Firestore serve its cache. The token refreshes once the
                // iPad is back online.
                return
            }
        }
        guard let classCode else {
            throw StudentSessionError.sessionExpired
        }
        try await claimSeat(classCode: classCode, studentID: studentID)
    }

    // MARK: - Helpers

    private static func isNotFound(_ error: NSError) -> Bool {
        error.domain == FunctionsErrorDomain
            && FunctionsErrorCode(rawValue: error.code) == .notFound
    }

    private func setError(_ message: String) async {
        // Class is @MainActor, so the assignment is already on main.
        self.loginError = message
    }
}

// MARK: - Errors

enum StudentSessionError: LocalizedError {
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return "Session expirée. Reconnectez-vous avec le code classe."
        }
    }
}

// MARK: - Data Extension

extension Data {
    func toString() -> String? {
        return String(data: self, encoding: .utf8)
    }
}
