//
//  AssignmentRepository.swift
//  MathClass
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import FirebaseFirestore
import Combine

/// Repository for Assignment and AssignmentExercise entities.
/// Manages CRUD and listeners for `assignments/{assignmentID}`
/// and `assignments/{assignmentID}/exercises/{assignmentExerciseID}`.
@MainActor
class AssignmentRepository: ObservableObject {
    @Published private(set) var assignments: [Assignment] = []
    @Published private(set) var assignmentExercises: [String: [AssignmentExercise]] = [:] // assignmentID -> exercises
    /// All assignments across the teacher's classes — populated by
    /// `startListeningAcrossClasses(classIDs:)`. Independent of the per-class
    /// `assignments` listener; used by the submission inbox.
    @Published private(set) var teacherAssignments: [Assignment] = []
    @Published var error: String?

    private let firebase = FirebaseService.shared
    private var assignmentsListener: ListenerRegistration?
    private var teacherAssignmentsListener: ListenerRegistration?
    private var exerciseListeners: [String: ListenerRegistration] = [:]
    private let collectionPath = "assignments"

    deinit {
        assignmentsListener?.remove()
        teacherAssignmentsListener?.remove()
        exerciseListeners.values.forEach { $0.remove() }
    }

    // MARK: - Collection Paths

    private func exercisesPath(assignmentID: String) -> String {
        "assignments/\(assignmentID)/exercises"
    }

    // MARK: - Assignments Listener

    /// Listen for all assignments for a class.
    func startListening(classID: String) {
        assignmentsListener?.remove()
        exerciseListeners.values.forEach { $0.remove() }
        exerciseListeners.removeAll()

        assignmentsListener = firebase.addQueryListener(
            from: collectionPath,
            whereField: "classID",
            isEqualTo: classID
        ) { [weak self] (assignments: [Assignment]) in
            self?.assignments = assignments.sorted { $0.createdAt > $1.createdAt }
            // Set up exercise listeners for each assignment
            for assignment in assignments {
                guard let assignmentID = assignment.id else { continue }
                self?.startExerciseListener(assignmentID: assignmentID)
            }
        }
    }

    func stopListening() {
        assignmentsListener?.remove()
        assignmentsListener = nil
        teacherAssignmentsListener?.remove()
        teacherAssignmentsListener = nil
        teacherAssignments = []
        exerciseListeners.values.forEach { $0.remove() }
        exerciseListeners.removeAll()
    }

    /// Listen for all assignments across the teacher's classes (cross-class
    /// scope, powers the submission inbox). Independent of the per-class
    /// `startListening(classID:)`. Limited to 10 class IDs per Firestore
    /// `whereField(_:in:)` cap; surplus classes log a warning.
    func startListeningAcrossClasses(classIDs: [String]) {
        teacherAssignmentsListener?.remove()

        guard !classIDs.isEmpty else {
            teacherAssignments = []
            return
        }

        let chunks = classIDs.chunked(into: 10)
        let firstChunk = chunks[0]
        if chunks.count > 1 {
            print("AssignmentRepository: listening on first 10 of \(classIDs.count) class IDs (Firestore 'in' cap)")
        }

        let query = firebase.db.collection(collectionPath)
            .whereField("classID", in: firstChunk)

        teacherAssignmentsListener = query.addSnapshotListener { [weak self] snapshot, error in
            if let error = error {
                print("Erreur écoute devoirs enseignant: \(error.localizedDescription)")
                self?.teacherAssignments = []
                return
            }
            guard let documents = snapshot?.documents else {
                self?.teacherAssignments = []
                return
            }
            do {
                self?.teacherAssignments = try documents.map { try $0.data(as: Assignment.self) }
                    .sorted { $0.createdAt > $1.createdAt }
            } catch {
                print("Erreur décodage devoirs enseignant: \(error.localizedDescription)")
                self?.teacherAssignments = []
            }
        }
    }

    private func startExerciseListener(assignmentID: String) {
        guard exerciseListeners[assignmentID] == nil else { return }

        let path = exercisesPath(assignmentID: assignmentID)
        let listener = firebase.addCollectionListener(collection: path) { [weak self] (exercises: [AssignmentExercise]) in
            self?.assignmentExercises[assignmentID] = exercises.sorted { $0.order < $1.order }
        }
        exerciseListeners[assignmentID] = listener
    }

    // MARK: - Active Assignments

    /// Get active assignments for a class.
    var activeAssignments: [Assignment] {
        assignments.filter { $0.isActive }
    }

    // MARK: - Assignment CRUD

    func createAssignment(_ assignment: Assignment) async throws -> String {
        let docRef = try await firebase.createDocument(assignment, in: collectionPath)
        return docRef.documentID
    }

    func updateAssignment(_ assignment: Assignment) async throws {
        guard let id = assignment.id else { return }
        try await firebase.updateDocument(assignment, in: collectionPath, documentID: id)
    }

    func deleteAssignment(id: String) async throws {
        try await firebase.deleteDocument(from: collectionPath, documentID: id)
        exerciseListeners[id]?.remove()
        exerciseListeners.removeValue(forKey: id)
        assignmentExercises.removeValue(forKey: id)
    }

    /// Toggle active state of an assignment.
    /// Routed through `FirebaseService.updateFields` instead of reaching
    /// into `firebase.db` directly — see CLAUDE.md.
    func setActive(_ isActive: Bool, assignmentID: String) async throws {
        try await firebase.updateFields(
            ["isActive": isActive],
            in: collectionPath,
            documentID: assignmentID
        )
    }

    // MARK: - Assignment Exercise CRUD

    func addExerciseToAssignment(
        _ assignmentExercise: AssignmentExercise,
        assignmentID: String
    ) async throws -> String {
        let docRef = try await firebase.createDocument(
            assignmentExercise,
            in: exercisesPath(assignmentID: assignmentID)
        )
        return docRef.documentID
    }

    func removeExerciseFromAssignment(
        exerciseID: String,
        assignmentID: String
    ) async throws {
        try await firebase.deleteDocument(
            from: exercisesPath(assignmentID: assignmentID),
            documentID: exerciseID
        )
    }

    /// Get all exercises for an assignment (one-shot).
    func getAssignmentExercises(assignmentID: String) async throws -> [AssignmentExercise] {
        let exercises: [AssignmentExercise] = try await firebase.getDocuments(
            from: exercisesPath(assignmentID: assignmentID)
        )
        return exercises.sorted { $0.order < $1.order }
    }

    /// Get exercises targeted at a specific student (for differentiation mode).
    func getExercisesForStudent(
        assignmentID: String,
        studentID: String
    ) async throws -> [AssignmentExercise] {
        let allExercises = try await getAssignmentExercises(assignmentID: assignmentID)
        return allExercises.filter { ae in
            // If no targeting, exercise is for all students
            guard let targetIDs = ae.targetStudentIDs else { return true }
            return targetIDs.contains(studentID)
        }
    }
}
