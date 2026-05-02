//
//  TeacherSignUpViewModel.swift
//  MathClass
//
//  Created by Xavier Morvan on 31.01.2025.
//

import Foundation
// Per CLAUDE.md, ViewModels must not import SwiftUI. Foundation is enough.

/// ViewModel for teacher account creation.
@MainActor
final class TeacherSignUpViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var isAccountCreated = false

    init() {
        // Teachers don't enter first/last names in the iOS sign-up form, so
        // we set defaults here. The previous approach hid SwiftUI fields and
        // populated them from a `.onAppear` chained on a hidden view — that
        // was both unreliable AND broke the Confirm-password field.
        self.firstName = "Enseignant"
        self.lastName = "MathClass"
    }

    var isValid: Bool {
        let emailIsValid = !email.isEmpty && email.contains("@")
        let passwordIsValid = !password.isEmpty
            && password.count >= 6
            && password.contains(where: { $0.isNumber })
            && password.contains(where: { $0.isUppercase })
        let passwordsMatch = password == confirmPassword
        let namesAreValid = !firstName.isEmpty && !lastName.isEmpty

        return emailIsValid && passwordIsValid && passwordsMatch && namesAreValid
    }

    func createAccount() async {
        do {
            var attempts = 0
            while attempts < 3 {
                do {
                    try await AuthenticationService.shared.createAccount(
                        email: email,
                        password: password,
                        firstName: firstName,
                        lastName: lastName
                    )
                    self.isAccountCreated = true
                    return
                } catch let error as NSError {
                    attempts += 1
                    if attempts == 3 || !error.domain.contains("Network") {
                        throw error
                    }
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        } catch {
            self.errorMessage = "Erreur : \(error.localizedDescription)\nVérifiez votre connexion Internet et réessayez."
            self.showError = true
        }
    }
}
