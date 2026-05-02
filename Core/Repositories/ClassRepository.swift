//
//  ClassRepository.swift
//  MathClass
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import FirebaseFirestore
import Combine

/// Repository for ClassRoom entities.
/// Manages CRUD and real-time listeners for `classes/{classID}`.
@MainActor
class ClassRepository: ObservableObject {
    @Published private(set) var classes: [ClassRoom] = []
    @Published private(set) var isLoading: Bool = false
    @Published var error: String?

    private let firebase = FirebaseService.shared
    private var listener: ListenerRegistration?
    private let collectionPath = "classes"

    deinit {
        listener?.remove()
    }

    // MARK: - Real-time Listener

    /// Start listening for all classes owned by a teacher.
    func startListening(teacherID: String) {
        listener?.remove()
        listener = firebase.addQueryListener(
            from: collectionPath,
            whereField: "teacherID",
            isEqualTo: teacherID
        ) { [weak self] (classes: [ClassRoom]) in
            self?.classes = classes.sorted { $0.name < $1.name }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - CRUD

    /// Create a new classroom. Returns the Firestore document ID.
    func createClass(_ classRoom: ClassRoom) async throws -> String {
        let docRef = try await firebase.createDocument(classRoom, in: collectionPath)
        return docRef.documentID
    }

    /// Fetch a single classroom by ID.
    func getClass(id: String) async throws -> ClassRoom {
        try await firebase.getDocument(id, from: collectionPath)
    }

    /// Fetch a classroom by its unique class code.
    func getClass(byCode code: String) async throws -> ClassRoom? {
        let results: [ClassRoom] = try await firebase.queryDocuments(
            from: collectionPath,
            whereField: "classCode",
            isEqualTo: code.uppercased()
        )
        return results.first
    }

    /// Update an existing classroom.
    func updateClass(_ classRoom: ClassRoom) async throws {
        guard let id = classRoom.id else { return }
        try await firebase.updateDocument(classRoom, in: collectionPath, documentID: id)
    }

    /// Delete a classroom and its subcollections.
    func deleteClass(id: String) async throws {
        // Note: Firestore does not cascade delete subcollections.
        // Subcollections (students, chapters) should be deleted first
        // or handled by a Cloud Function.
        try await firebase.deleteDocument(from: collectionPath, documentID: id)
    }
}
