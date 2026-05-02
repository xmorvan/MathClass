//
//  StudentSessionManager.swift
//  MathClass
//
//  Created on 04.09.2025.
//

import Foundation
import SwiftUI
import FirebaseFirestore

/// Manages student sessions via class code + name selection.
/// Students authenticate by entering a class code (MX-XXXX) and selecting their name.
/// The session is persisted in the Keychain so the student doesn't need to re-enter it.
@MainActor
final class StudentSessionManager: ObservableObject {
    static let shared = StudentSessionManager()

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

        // Update device token on the student document
        do {
            var updatedStudent = student
            updatedStudent.deviceToken = deviceToken
            try await DataService.shared.studentRepository.updateStudent(updatedStudent, classID: classID)
        } catch {
            print("Erreur mise à jour device token: \(error.localizedDescription)")
        }

        // Class is @MainActor, so direct mutation is safe (and any await
        // suspension above resumes on the MainActor automatically).
        self.currentStudent = student
        self.currentClassID = classID
        self.isLoggedIn = true
        self.loginError = nil

        // Set student role on AuthenticationService
        AuthenticationService.shared.setStudentRole()
    }

    // MARK: - Logout

    func logout() {
        // Clear Keychain
        _ = KeychainHelper.shared.delete(key: studentIDKey)
        _ = KeychainHelper.shared.delete(key: classIDKey)

        // Reset state
        currentStudent = nil
        currentClassID = nil
        isLoggedIn = false
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
            return
        }

        Task {
            do {
                let student: Student = try await FirebaseService.shared.getDocument(
                    studentID,
                    from: "classes/\(classID)/students"
                )

                // Inherits MainActor from the enclosing class, no explicit hop needed.
                self.currentStudent = student
                self.currentClassID = classID
                self.isLoggedIn = true

                AuthenticationService.shared.setStudentRole()
            } catch {
                // Invalid session — clear it
                _ = KeychainHelper.shared.delete(key: studentIDKey)
                _ = KeychainHelper.shared.delete(key: classIDKey)
            }
        }
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
