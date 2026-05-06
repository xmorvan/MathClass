//
//  SubmissionRepository.swift
//  MathClass
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import FirebaseFirestore
import Combine

/// Repository for Submission entities.
/// Manages CRUD and real-time listeners for `submissions/{submissionID}`.
@MainActor
class SubmissionRepository: ObservableObject {
    @Published private(set) var submissions: [Submission] = []
    @Published var error: String?

    private let firebase = FirebaseService.shared
    private var listener: ListenerRegistration?
    private let collectionPath = "submissions"

    deinit {
        listener?.remove()
    }

    // MARK: - Real-time Listeners

    /// Listen for all submissions within an assignment (teacher view).
    func startListening(assignmentID: String) {
        listener?.remove()
        listener = firebase.addQueryListener(
            from: collectionPath,
            whereField: "assignmentID",
            isEqualTo: assignmentID
        ) { [weak self] (submissions: [Submission]) in
            self?.submissions = submissions.sorted { $0.timestamp > $1.timestamp }
        }
    }

    /// Listen for all recent submissions across the teacher's active
    /// assignments. Powers `SubmissionInboxView_macOS`.
    ///
    /// Firestore caps `whereField(_:in:)` at 10 values. For MVP we listen
    /// on the first 10 assignment IDs and log a warning if the teacher has
    /// more — this keeps the listener simple and is sufficient for early
    /// classroom use. A future fix would fan out one listener per chunk
    /// and merge the results.
    func startListeningForTeacher(classAssignmentIDs: [String]) {
        listener?.remove()

        guard !classAssignmentIDs.isEmpty else {
            submissions = []
            return
        }

        let chunked = classAssignmentIDs.chunked(into: 10)
        let firstChunk = chunked[0]
        if chunked.count > 1 {
            print("SubmissionRepository: listening on first 10 of \(classAssignmentIDs.count) assignment IDs (Firestore 'in' cap)")
        }

        let query = firebase.db.collection(collectionPath)
            .whereField("assignmentID", in: firstChunk)
            .order(by: "timestamp", descending: true)
            .limit(to: 100)

        listener = query.addSnapshotListener { [weak self] snapshot, error in
            if let error = error {
                print("Erreur écoute soumissions enseignant: \(error.localizedDescription)")
                self?.submissions = []
                return
            }
            guard let documents = snapshot?.documents else {
                self?.submissions = []
                return
            }
            do {
                self?.submissions = try documents.map { try $0.data(as: Submission.self) }
            } catch {
                print("Erreur décodage soumissions enseignant: \(error.localizedDescription)")
                self?.submissions = []
            }
        }
    }

    /// Listen for a student's submissions within an assignment.
    func startListening(studentID: String, assignmentID: String) {
        listener?.remove()
        // Use a compound listener — Firestore requires a composite index for this
        let query = firebase.db.collection(collectionPath)
            .whereField("studentID", isEqualTo: studentID)
            .whereField("assignmentID", isEqualTo: assignmentID)
        listener = query.addSnapshotListener { [weak self] snapshot, error in
            if let error = error {
                print("Erreur écoute soumissions: \(error.localizedDescription)")
                self?.submissions = []
                return
            }
            guard let documents = snapshot?.documents else {
                self?.submissions = []
                return
            }
            do {
                self?.submissions = try documents.map { try $0.data(as: Submission.self) }
                    .sorted { $0.timestamp > $1.timestamp }
            } catch {
                print("Erreur décodage soumissions: \(error.localizedDescription)")
                self?.submissions = []
            }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - CRUD

    /// Create a new submission. Returns the Firestore document ID.
    func createSubmission(_ submission: Submission) async throws -> String {
        let docRef = try await firebase.createDocument(submission, in: collectionPath)
        return docRef.documentID
    }

    /// Update a submission (e.g., after correction results arrive).
    func updateSubmission(_ submission: Submission) async throws {
        guard let id = submission.id else { return }
        try await firebase.updateDocument(submission, in: collectionPath, documentID: id)
    }

    // MARK: - Queries

    /// Get all submissions for a specific exercise (for statistics).
    func getSubmissions(exerciseID: String) async throws -> [Submission] {
        try await firebase.queryDocuments(
            from: collectionPath,
            whereField: "exerciseID",
            isEqualTo: exerciseID
        )
    }

    /// Get all submissions by a student.
    func getSubmissions(studentID: String) async throws -> [Submission] {
        try await firebase.queryDocuments(
            from: collectionPath,
            whereField: "studentID",
            isEqualTo: studentID
        )
    }

    /// Get all submissions for an assignment.
    func getSubmissions(assignmentID: String) async throws -> [Submission] {
        try await firebase.queryDocuments(
            from: collectionPath,
            whereField: "assignmentID",
            isEqualTo: assignmentID
        )
    }

    /// Check if a student has already submitted for an exercise within an assignment.
    func getExistingSubmission(
        studentID: String,
        exerciseID: String,
        assignmentID: String,
        attemptNumber: Int
    ) async throws -> Submission? {
        let query = firebase.db.collection(collectionPath)
            .whereField("studentID", isEqualTo: studentID)
            .whereField("exerciseID", isEqualTo: exerciseID)
            .whereField("assignmentID", isEqualTo: assignmentID)
            .whereField("attemptNumber", isEqualTo: attemptNumber)
        let snapshot = try await query.getDocuments()
        return try snapshot.documents.first.map { try $0.data(as: Submission.self) }
    }

    /// Get the number of consecutive first-attempt successes for a student
    /// in a given assignment (used for levels mode progression).
    func getConsecutiveSuccessCount(
        studentID: String,
        assignmentID: String,
        currentDifficultyLevel: Int,
        exerciseIDs: [String]
    ) async throws -> Int {
        let allSubmissions = try await getSubmissions(assignmentID: assignmentID)
        let studentSubmissions = allSubmissions
            .filter { $0.studentID == studentID }
            .sorted { $0.timestamp > $1.timestamp } // Most recent first

        var count = 0
        for submission in studentSubmissions {
            guard exerciseIDs.contains(submission.exerciseID) else { continue }
            if submission.attemptNumber == 1 && submission.finalResult == .success1st {
                count += 1
            } else {
                break // Streak broken
            }
        }
        return count
    }
}
