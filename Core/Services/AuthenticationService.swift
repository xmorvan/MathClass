//
//  AuthenticationService.swift
//  MathClass
//
//  Created by Xavier Morvan on 31.01.2025.
//

import FirebaseAuth
import FirebaseFirestore

/// Manages Firebase Authentication.
/// - Teachers: email + password accounts with a `users/{uid}` profile.
/// - Students: anonymous accounts. `StudentSessionManager` binds them to one
///   student via the `claim_student_seat` Cloud Function, which sets the
///   custom claims the security rules check.
@MainActor
final class AuthenticationService: ObservableObject {
    static let shared = AuthenticationService()
    private let auth: Auth
    private let firebase = FirebaseService.shared

    @Published var currentUser: User? = nil
    @Published var userRole: UserRole? = nil
    /// True when a signed-in teacher's `users/{uid}` profile couldn't be
    /// loaded (missing doc, or offline with nothing cached). The root view
    /// offers "retry" / "sign out" instead of an endless spinner.
    @Published var roleLookupFailed: Bool = false

    private init() {
        self.auth = Auth.auth()

        // Firebase delivers auth-state callbacks on a background queue. Hop
        // explicitly to MainActor so all @Published mutations stay on main —
        // this is required now that the class is @MainActor.
        _ = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.currentUser = user
                self.roleLookupFailed = false
                if let user = user, !user.isAnonymous {
                    await self.fetchUserRole(userId: user.uid)
                } else if user == nil {
                    self.userRole = nil
                }
                // Anonymous (student) accounts have no users/{uid} profile;
                // StudentSessionManager sets the student role itself.
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

        try await firebase.setFields(
            [
                "email": email,
                "firstName": firstName,
                "lastName": lastName,
                "role": UserRole.teacher.rawValue,
                "createdAt": FieldValue.serverTimestamp(),
            ],
            in: "users",
            documentID: authResult.user.uid
        )
        self.userRole = .teacher
        self.roleLookupFailed = false
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
        self.roleLookupFailed = false
    }

    /// Retry loading the teacher profile after a failed lookup.
    func retryRoleLookup() async {
        guard let user = currentUser, !user.isAnonymous else { return }
        roleLookupFailed = false
        await fetchUserRole(userId: user.uid)
    }

    /// True when a teacher (non-anonymous account) is signed in.
    var isTeacherAccount: Bool {
        guard let user = currentUser else { return false }
        return !user.isAnonymous
    }

    // MARK: - Student Accounts (anonymous)

    /// Return the current anonymous account, creating one if needed.
    /// Signs out a teacher account first: an iPad is used either by a
    /// teacher or by a student, never both at once.
    func signInAnonymouslyIfNeeded() async throws -> User {
        if let user = auth.currentUser, user.isAnonymous {
            return user
        }
        if auth.currentUser != nil {
            try auth.signOut()
        }
        return try await auth.signInAnonymously().user
    }

    /// Sign out the anonymous student account (student logout).
    func signOutStudent() {
        guard let user = auth.currentUser, user.isAnonymous else { return }
        do {
            try auth.signOut()
        } catch {
            print("AuthenticationService.signOutStudent error: \(error.localizedDescription)")
        }
    }

    /// Set the role to student once the anonymous account holds its claims.
    /// Class is @MainActor, so the assignment is guaranteed to publish on main.
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
        // Never leave a teacher on the loading screen: past 15 s without an
        // answer, show the retry screen.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, self.userRole == nil, !self.roleLookupFailed,
                  let user = self.currentUser, !user.isAnonymous, user.uid == userId else { return }
            print("AuthenticationService.fetchUserRole timed out")
            self.roleLookupFailed = true
        }
        do {
            let teacher: Teacher = try await firebase.getDocument(userId, from: "users")
            if let role = UserRole(rawValue: teacher.role) {
                self.userRole = role
            } else {
                roleLookupFailed = true
            }
        } catch {
            // Doc-not-found is the common case for a freshly-created
            // anonymous student session — they have no /users/{uid}.
            // Leave role unset; the StudentSessionManager will set it
            // explicitly via `setStudentRole()` after linkSession.
            print("AuthenticationService.fetchUserRole — no role for uid (\((error as NSError).code))")
            if let user = currentUser, !user.isAnonymous, user.uid == userId, userRole == nil {
                roleLookupFailed = true
            }
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
