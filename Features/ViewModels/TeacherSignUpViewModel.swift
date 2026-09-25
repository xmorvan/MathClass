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
            self.errorMessage = LocalizationManager.shared.format("Erreur : %@\nVérifiez votre connexion Internet et réessayez.", error.localizedDescription)
            self.showError = true
        }
    }
}
