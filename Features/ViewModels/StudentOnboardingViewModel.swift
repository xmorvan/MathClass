//
//  StudentOnboardingViewModel.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import SwiftUI

/// ViewModel for the student onboarding flow.
/// Manages: code entry → class lookup → name selection → session creation.
@MainActor
class StudentOnboardingViewModel: ObservableObject {

    enum Step {
        case enterCode
        case selectName
    }

    // MARK: - Published State

    @Published var step: Step = .enterCode
    @Published var classCode: String = ""
    @Published var matchedClass: JoinableClass?
    @Published var studentsInClass: [Student] = []
    @Published var isLookingUp: Bool = false
    @Published var isLoggingIn: Bool = false
    /// Flips to true once the seat is claimed; the view dismisses on it.
    @Published var didLogIn: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""

    private let sessionManager = StudentSessionManager.shared

    // MARK: - Actions

    /// Look up the class by its MX-XXXX code.
    func lookupClass() {
        isLookingUp = true
        Task {
            do {
                if let joinedClass = try await sessionManager.joinClass(code: classCode) {
                    self.matchedClass = joinedClass
                    self.studentsInClass = joinedClass.students
                    self.step = .selectName
                } else {
                    self.errorMessage = "Code classe introuvable. Vérifiez le code et réessayez."
                    self.showError = true
                }
            } catch {
                self.errorMessage = "Erreur: \(error.localizedDescription)"
                self.showError = true
            }
            self.isLookingUp = false
        }
    }

    /// Log in as the selected student.
    func selectStudent(_ student: Student) {
        guard let joinedClass = matchedClass, !isLoggingIn else { return }
        isLoggingIn = true
        Task {
            await sessionManager.login(student: student, joinedClass: joinedClass)
            self.isLoggingIn = false
            if sessionManager.isLoggedIn {
                self.didLogIn = true
            } else {
                self.errorMessage = sessionManager.loginError ?? "Connexion impossible. Réessayez."
                self.showError = true
            }
        }
    }

    /// Go back to the code entry step.
    func goBack() {
        step = .enterCode
        matchedClass = nil
        studentsInClass = []
    }
}
