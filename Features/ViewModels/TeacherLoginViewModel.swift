//
//  TeacherLoginViewModel.swift
//  MathClass
//
//  Sign-in for an existing teacher account (iPad and Mac).
//

import Foundation

class TeacherLoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var isLoggedIn = false

    var isValid: Bool {
        !email.isEmpty && !password.isEmpty && email.contains("@")
    }

    @MainActor
    func login() async {
        do {
            try await AuthenticationService.shared.signIn(email: email, password: password)
            self.isLoggedIn = true
        } catch {
            self.errorMessage = Self.message(for: error)
            self.showError = true
        }
    }

    /// Firebase Auth errors are English and technical; map the common ones.
    static func message(for error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == "FIRAuthErrorDomain" else {
            return LocalizationManager.shared.format("Connexion impossible : %@", error.localizedDescription)
        }
        switch nsError.code {
        case 17004, 17009, 17011:   // invalid credential, wrong password, user not found
            return "E-mail ou mot de passe incorrect.".tr
        case 17008:                 // invalid email
            return "Adresse e-mail invalide.".tr
        case 17010:                 // too many requests
            return "Trop de tentatives. Réessayez dans quelques minutes.".tr
        case 17020:                 // network error
            return "Pas de connexion internet.".tr
        default:
            return LocalizationManager.shared.format("Connexion impossible : %@", error.localizedDescription)
        }
    }
}
