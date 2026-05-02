//
//  ExerciseRepository.swift
//  MathClass
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import FirebaseFirestore
import Combine

/// Repository for Exercise entities.
/// Manages CRUD and real-time listeners for top-level `exercises/{exerciseID}`.
@MainActor
class ExerciseRepository: ObservableObject {
    @Published private(set) var exercises: [Exercise] = []
    @Published private(set) var isLoading: Bool = false
    @Published var error: String?

    private let firebase = FirebaseService.shared
    private var listener: ListenerRegistration?
    private let collectionPath = "exercises"

    deinit {
        listener?.remove()
    }

    // MARK: - Real-time Listener

    /// Start listening for all exercises owned by a teacher.
    func startListening(teacherID: String) {
        listener?.remove()
        listener = firebase.addQueryListener(
            from: collectionPath,
            whereField: "teacherID",
            isEqualTo: teacherID
        ) { [weak self] (exercises: [Exercise]) in
            self?.exercises = exercises.sorted { $0.title < $1.title }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - CRUD

    /// Create a new exercise. Returns the Firestore document ID.
    func createExercise(_ exercise: Exercise) async throws -> String {
        let docRef = try await firebase.createDocument(exercise, in: collectionPath)
        return docRef.documentID
    }

    /// Fetch a single exercise by ID.
    func getExercise(id: String) async throws -> Exercise {
        try await firebase.getDocument(id, from: collectionPath)
    }

    /// Fetch all exercises by a teacher.
    func getExercises(teacherID: String) async throws -> [Exercise] {
        try await firebase.queryDocuments(
            from: collectionPath,
            whereField: "teacherID",
            isEqualTo: teacherID
        )
    }

    /// Fetch exercises belonging to a specific chapter.
    func getExercises(chapterID: String) async throws -> [Exercise] {
        try await firebase.queryDocuments(
            from: collectionPath,
            whereField: "chapterID",
            isEqualTo: chapterID
        )
    }

    /// Fetch exercises by their IDs (e.g., for loading assignment exercises).
    func getExercises(ids: [String]) async throws -> [Exercise] {
        guard !ids.isEmpty else { return [] }
        // Firestore `in` queries support max 30 values
        var allExercises: [Exercise] = []
        for chunk in ids.chunked(into: 30) {
            let snapshot = try await firebase.db.collection(collectionPath)
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            let batch = try snapshot.documents.map { try $0.data(as: Exercise.self) }
            allExercises.append(contentsOf: batch)
        }
        return allExercises
    }

    /// Update an existing exercise.
    func updateExercise(_ exercise: Exercise) async throws {
        guard let id = exercise.id else { return }
        try await firebase.updateDocument(exercise, in: collectionPath, documentID: id)
    }

    /// Delete an exercise.
    func deleteExercise(id: String) async throws {
        try await firebase.deleteDocument(from: collectionPath, documentID: id)
    }
}

// MARK: - Array Chunking Helper

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
