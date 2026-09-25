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
    /// Multi-chunk listeners for the cross-class teacher view. Firestore
    /// `whereField(_:in:)` is capped at 30 values, so we fan out and merge
    /// the per-chunk results keyed by assignmentID (ISSUE-005).
    private var teacherChunkListeners: [ListenerRegistration] = []
    private var teacherChunkResults: [Int: [Assignment]] = [:]
    private var exerciseListeners: [String: ListenerRegistration] = [:]
    private let collectionPath = "assignments"

    deinit {
        assignmentsListener?.remove()
        teacherChunkListeners.forEach { $0.remove() }
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
            guard let self else { return }
            self.assignments = assignments.sorted { $0.createdAt > $1.createdAt }
            // Per-assignment exercise listeners: install for newly-seen IDs,
            // tear down for assignments that disappeared from the query.
            // Without the teardown, deleted assignments leaked listeners
            // for the lifetime of the repository (ISSUE-014 §4.A.2).
            let newIDs: Set<String> = Set(assignments.compactMap(\.id))
            for (oldID, listener) in self.exerciseListeners where !newIDs.contains(oldID) {
                listener.remove()
                self.exerciseListeners.removeValue(forKey: oldID)
                self.assignmentExercises.removeValue(forKey: oldID)
            }
            for assignmentID in newIDs {
                self.startExerciseListener(assignmentID: assignmentID)
            }
        }
    }

    func stopListening() {
        assignmentsListener?.remove()
        assignmentsListener = nil
        teacherChunkListeners.forEach { $0.remove() }
        teacherChunkListeners = []
        teacherChunkResults = [:]
        teacherAssignments = []
        exerciseListeners.values.forEach { $0.remove() }
        exerciseListeners.removeAll()
    }

    /// Listen for all assignments across the teacher's classes (cross-class
    /// scope, powers the submission inbox). Independent of the per-class
    /// `startListening(classID:)`. Fans out one listener per 30-class chunk
    /// and merges the results keyed by assignmentID (ISSUE-005 — previously
    /// truncated at 10 and silently lost the rest).
    func startListeningAcrossClasses(classIDs: [String]) {
        teacherChunkListeners.forEach { $0.remove() }
        teacherChunkListeners = []
        teacherChunkResults = [:]

        guard !classIDs.isEmpty else {
            teacherAssignments = []
            return
        }

        let chunks = classIDs.chunked(into: 30)
        for (index, chunk) in chunks.enumerated() {
            let query = firebase.db.collection(collectionPath)
                .whereField("classID", in: chunk)

            let registration = query.addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error = error {
                    print("Erreur écoute devoirs enseignant (chunk \(index)): \(error.localizedDescription)")
                    self.teacherChunkResults[index] = []
                    self.recomputeMergedTeacherAssignments()
                    return
                }
                guard let documents = snapshot?.documents else {
                    self.teacherChunkResults[index] = []
                    self.recomputeMergedTeacherAssignments()
                    return
                }
                do {
                    let parsed = try documents.map { try $0.data(as: Assignment.self) }
                    self.teacherChunkResults[index] = parsed
                } catch {
                    print("Erreur décodage devoirs enseignant (chunk \(index)): \(error.localizedDescription)")
                    self.teacherChunkResults[index] = []
                }
                self.recomputeMergedTeacherAssignments()
            }
            teacherChunkListeners.append(registration)
        }
    }

    /// Merge per-chunk teacher assignments by ID, sorted newest first.
    private func recomputeMergedTeacherAssignments() {
        var seen: Set<String> = []
        var merged: [Assignment] = []
        for chunk in teacherChunkResults.values {
            for assignment in chunk {
                guard let id = assignment.id else { continue }
                if seen.insert(id).inserted {
                    merged.append(assignment)
                }
            }
        }
        merged.sort { $0.createdAt > $1.createdAt }
        teacherAssignments = merged
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
    /// Mirrors `SessionRepository.exercisesForStudent` for the legacy flat
    /// `Assignment` path: an exercise is included when (a) it has no
    /// targeting at all, OR (b) `targetStudentIDs` lists the student, OR
    /// (c) `targetGroupID` is one of the student's groups. Without (c),
    /// any exercise assigned via group targeting silently disappeared on
    /// the legacy code path (ISSUE-014).
    func getExercisesForStudent(
        assignmentID: String,
        studentID: String,
        studentGroupIDs: Set<String> = []
    ) async throws -> [AssignmentExercise] {
        let allExercises = try await getAssignmentExercises(assignmentID: assignmentID)
        return allExercises.filter { ae in
            let hasStudentTarget = !(ae.targetStudentIDs?.isEmpty ?? true)
            let hasGroupTarget = (ae.targetGroupID?.isEmpty == false)
            if !hasStudentTarget && !hasGroupTarget {
                return true  // untargeted exercise: for everyone
            }
            if let ids = ae.targetStudentIDs, ids.contains(studentID) {
                return true
            }
            if let gid = ae.targetGroupID, studentGroupIDs.contains(gid) {
                return true
            }
            return false
        }
    }
}
