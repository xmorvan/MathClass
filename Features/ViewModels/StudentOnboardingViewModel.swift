//
//  StudentOnboardingViewModel.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import Combine

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
    @Published var matchedClass: ClassRoom?
    @Published var studentsInClass: [Student] = []
    @Published var isLookingUp: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""

    private let sessionManager = StudentSessionManager.shared

    // MARK: - Actions

    /// Look up the class by its MX-XXXX code.
    func lookupClass() {
        isLookingUp = true
        Task {
            do {
                if let classRoom = try await sessionManager.lookupClass(code: classCode) {
                    let classID = classRoom.id ?? ""
                    let students = try await sessionManager.getStudents(classID: classID)

                    self.matchedClass = classRoom
                    self.studentsInClass = students
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
        guard let classID = matchedClass?.id else { return }
        Task {
            await sessionManager.login(student: student, classID: classID)
        }
    }

    /// Go back to the code entry step.
    func goBack() {
        step = .enterCode
        matchedClass = nil
        studentsInClass = []
    }
}
