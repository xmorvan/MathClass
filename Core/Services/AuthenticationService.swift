//
//  AuthenticationService.swift
//  MathClass
//
//  Created by Xavier Morvan on 31.01.2025.
//

import FirebaseAuth
import FirebaseFirestore

/// Manages Firebase Authentication for teachers.
/// Students do not use Firebase Auth — they authenticate via class code + name selection.
@MainActor
final class AuthenticationService: ObservableObject {
    static let shared = AuthenticationService()
    private let auth: Auth
    private let db: Firestore

    @Published var currentUser: User? = nil
    @Published var userRole: UserRole? = nil

    private init() {
        self.auth = Auth.auth()
        self.db = Firestore.firestore()

        // Firebase delivers auth-state callbacks on a background queue. Hop
        // explicitly to MainActor so all @Published mutations stay on main —
        // this is required now that the class is @MainActor.
        _ = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.currentUser = user
                if let user = user {
                    await self.fetchUserRole(userId: user.uid)
                } else {
                    self.userRole = nil
                }
            }
        }
    }

    // MARK: - Teacher Account Management

    /// Create a new teacher account with email and password.
    func createAccount(
        email: String,
        password: String,
        firstName: String,
        lastName: String
    ) async throws {
        let authResult = try await auth.createUser(withEmail: email, password: password)

        let userData: [String: Any] = [
            "email": email,
            "firstName": firstName,
            "lastName": lastName,
            "role": UserRole.teacher.rawValue,
            "createdAt": Timestamp()
        ]

        try await db.collection("users").document(authResult.user.uid).setData(userData)
        self.userRole = .teacher
    }

    /// Sign in an existing teacher.
    func signIn(email: String, password: String) async throws {
        _ = try await auth.signIn(withEmail: email, password: password)
    }

    /// Sign out the current teacher.
    func signOut() throws {
        try auth.signOut()
        self.currentUser = nil
        self.userRole = nil
    }

    // MARK: - Student Role (no Firebase Auth)

    /// Set the role to student for the current session (students don't use Firebase Auth).
    /// Class is @MainActor, so the assignment is guaranteed to publish on main —
    /// no more DispatchQueue.main.async dance.
    func setStudentRole() {
        userRole = .student
    }

    /// Clear student role on logout.
    func clearStudentRole() {
        userRole = nil
    }

    // MARK: - Role Fetching

    /// Async because we await the Firestore fetch from MainActor and don't
    /// need a closure-based completion path anymore.
    private func fetchUserRole(userId: String) async {
        do {
            let snapshot = try await db.collection("users").document(userId).getDocument()
            if let data = snapshot.data(),
               let roleString = data["role"] as? String,
               let role = UserRole(rawValue: roleString) {
                self.userRole = role
            }
        } catch {
            print("AuthenticationService.fetchUserRole error: \(error.localizedDescription)")
        }
    }

    // MARK: - Debug Helpers

    #if DEBUG
    /// Test account constants for development only.
    static let testTeacherEmail = "testteacher@example.com"
    static let testPassword = "Test123!"

    func loginAsTestTeacher() async throws {
        try await signIn(email: Self.testTeacherEmail, password: Self.testPassword)
    }
    #endif
}
