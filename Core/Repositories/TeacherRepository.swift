//
//  TeacherRepository.swift
//  MathClass
//
//  Created by Xavier Morvan on 19.03.2026.
//

import Foundation
import FirebaseFirestore

/// Repository for Teacher profile data.
/// Manages reads and updates for `users/{teacherID}`.
@MainActor
class TeacherRepository: ObservableObject {
    @Published private(set) var teacher: Teacher?
    @Published private(set) var isLoading: Bool = false
    @Published var error: String?

    private let firebase = FirebaseService.shared
    private var listener: ListenerRegistration?
    private let collectionPath = "users"

    deinit {
        listener?.remove()
    }

    // MARK: - Real-time Listener

    /// Start listening to the teacher's profile document.
    func startListening(teacherID: String) {
        listener?.remove()
        listener = firebase.addDocumentListener(
            documentID: teacherID,
            in: collectionPath
        ) { [weak self] (teacher: Teacher?) in
            self?.teacher = teacher
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - CRUD

    /// Fetch the teacher profile once.
    func getTeacher(id: String) async throws -> Teacher {
        try await firebase.getDocument(id, from: collectionPath)
    }

    /// Update the teacher's profile fields.
    func updateTeacher(_ teacher: Teacher) async throws {
        guard let id = teacher.id else { return }
        try await firebase.updateDocument(teacher, in: collectionPath, documentID: id)
    }
}
