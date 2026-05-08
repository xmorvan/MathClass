//
//  AuthProvider.swift
//  MathClass
//
//  Protocol that abstracts the teacher authentication backend so SSO,
//  email-link, or paid-tier providers can drop in alongside the
//  current Firebase email/password implementation without touching
//  every call site. The default implementation lives in
//  `AuthenticationService` (which adopts this protocol). A future
//  refactor can swap the concrete instance via dependency injection.
//

import Foundation
import FirebaseAuth

/// Authentication-provider contract used by ViewModels and views.
/// Today this is satisfied by `AuthenticationService` (Firebase email +
/// password). Adopters keep `currentUser`/`userRole` semantics so call
/// sites are provider-agnostic.
@MainActor
protocol AuthProvider: AnyObject {
    /// The signed-in Firebase user, if any. `nil` when no teacher is
    /// authenticated.
    var currentUser: User? { get }
    /// The role of the signed-in user (`.teacher`, `.student`, or `nil`).
    var userRole: UserRole? { get }

    /// Create a teacher account.
    func createAccount(email: String, password: String, firstName: String, lastName: String) async throws
    /// Sign in an existing teacher.
    func signIn(email: String, password: String) async throws
    /// Sign out the current teacher.
    func signOut() throws
}

extension AuthenticationService: AuthProvider {}
