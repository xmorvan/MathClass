//
//  StudentRepository.swift
//  MathClass
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import FirebaseFirestore
import Combine

/// Repository for Student entities.
/// Manages CRUD and real-time listeners for `classes/{classID}/students/{studentID}`.
@MainActor
class StudentRepository: ObservableObject {
    @Published private(set) var students: [Student] = []
    @Published private(set) var isLoading: Bool = false
    @Published var error: String?

    private let firebase = FirebaseService.shared
    private var listener: ListenerRegistration?

    deinit {
        listener?.remove()
    }

    // MARK: - Collection Path

    private func collectionPath(classID: String) -> String {
        "classes/\(classID)/students"
    }

    // MARK: - Real-time Listener

    /// Start listening for all students in a class.
    func startListening(classID: String) {
        listener?.remove()
        let path = collectionPath(classID: classID)
        listener = firebase.addCollectionListener(collection: path) { [weak self] (students: [Student]) in
            self?.students = students.sorted { $0.lastName < $1.lastName }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - CRUD

    /// Add a student to a class. Returns the Firestore document ID.
    func addStudent(_ student: Student, classID: String) async throws -> String {
        var studentToSave = student
        studentToSave.classID = classID
        let docRef = try await firebase.createDocument(
            studentToSave,
            in: collectionPath(classID: classID)
        )
        return docRef.documentID
    }

    /// Add multiple students to a class (batch import). Uses a single
    /// Firestore batch — a 30-row paste used to fire 30 sequential writes
    /// (one round-trip each); the batch makes it one round-trip total.
    func addStudents(_ students: [Student], classID: String) async throws {
        let prepared = students.map { student -> Student in
            var copy = student
            copy.classID = classID
            return copy
        }
        try await firebase.createDocuments(
            prepared,
            in: collectionPath(classID: classID),
            idFor: { $0.id }
        )
    }

    /// Fetch a single student by ID.
    func getStudent(id: String, classID: String) async throws -> Student {
        try await firebase.getDocument(id, from: collectionPath(classID: classID))
    }

    /// Fetch all students in a class.
    func getStudents(classID: String) async throws -> [Student] {
        let students: [Student] = try await firebase.getDocuments(
            from: collectionPath(classID: classID)
        )
        return students.sorted { $0.lastName < $1.lastName }
    }

    /// Update a student's information.
    func updateStudent(_ student: Student, classID: String) async throws {
        guard let id = student.id else { return }
        try await firebase.updateDocument(
            student,
            in: collectionPath(classID: classID),
            documentID: id
        )
    }

    /// Delete a student from a class.
    func deleteStudent(id: String, classID: String) async throws {
        try await firebase.deleteDocument(
            from: collectionPath(classID: classID),
            documentID: id
        )
    }

    /// Reset a student's device link (teacher action).
    /// Routed through `FirebaseService.updateFields` instead of touching
    /// `firebase.db` directly — see CLAUDE.md.
    func resetDeviceLink(studentID: String, classID: String) async throws {
        try await firebase.updateFields(
            ["deviceToken": FieldValue.delete()],
            in: collectionPath(classID: classID),
            documentID: studentID
        )
    }
}
