//
//  TeacherProfileViewModel.swift
//  MathClass
//
//  Created by Xavier Morvan on 19.03.2026.
//

import Foundation

/// ViewModel for the teacher profile view.
/// Loads and saves teacher profile data (firstName, lastName).
@MainActor
class TeacherProfileViewModel: ObservableObject {
    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var email: String = ""
    @Published var createdAt: Date = Date()
    @Published var isSaving: Bool = false
    @Published var isLoading: Bool = true
    @Published var error: String?
    @Published var saveSuccess: Bool = false

    // Reuse the shared TeacherRepository so this view sees the same listener
    // state as the rest of the app — instantiating our own meant edits made
    // elsewhere never refreshed the profile screen.
    private let teacherRepo = DataService.shared.teacherRepository
    private var teacherID: String?

    // MARK: - Load

    func load() async {
        guard let uid = AuthenticationService.shared.currentUser?.uid else { return }
        teacherID = uid
        isLoading = true
        error = nil

        do {
            let teacher = try await teacherRepo.getTeacher(id: uid)
            firstName = teacher.firstName
            lastName = teacher.lastName
            email = teacher.email
            createdAt = teacher.createdAt
        } catch {
            self.error = "Impossible de charger le profil."
        }

        isLoading = false
    }

    // MARK: - Save

    func save() async {
        guard let teacherID else { return }
        guard !firstName.trimmingCharacters(in: .whitespaces).isEmpty,
              !lastName.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "Le prénom et le nom ne peuvent pas être vides."
            return
        }

        isSaving = true
        error = nil
        saveSuccess = false

        do {
            var teacher = Teacher(
                email: email,
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                lastName: lastName.trimmingCharacters(in: .whitespaces),
                role: UserRole.teacher.rawValue,
                createdAt: createdAt
            )
            teacher.id = teacherID
            try await teacherRepo.updateTeacher(teacher)
            saveSuccess = true
        } catch {
            self.error = "Impossible de sauvegarder le profil."
        }

        isSaving = false
    }
}
