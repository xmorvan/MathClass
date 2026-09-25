//
//  SubmissionRepository.swift
//  MathClass
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import FirebaseAuth
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
    /// Multi-chunk listeners for the cross-assignment teacher inbox. Firestore
    /// `whereField(_:in:)` is capped at 30 values, so the inbox query is
    /// fanned out and the per-chunk results are merged here, keyed by
    /// submissionID (ISSUE-005). Empty when only the single-listener APIs
    /// are in use.
    private var teacherChunkListeners: [ListenerRegistration] = []
    private var teacherChunkResults: [Int: [Submission]] = [:]
    private let collectionPath = "submissions"

    deinit {
        listener?.remove()
        teacherChunkListeners.forEach { $0.remove() }
    }

    // MARK: - Caller Scope

    /// Base query pinned to the caller. The security rules only let a
    /// teacher read submissions stamped with their `teacherID` and a student
    /// read their own, and Firestore refuses any query that could return
    /// something else — so every read starts here. `studentID` narrows a
    /// teacher's query to one student; a student may only ask for
    /// themselves. Nil when nobody (or the wrong student) is signed in.
    private func scopedQuery(studentID: String? = nil) -> Query? {
        guard let user = AuthenticationService.shared.currentUser else { return nil }
        let base = firebase.db.collection(collectionPath)
        if user.isAnonymous {
            guard let ownID = StudentSessionManager.shared.currentStudent?.id,
                  studentID == nil || studentID == ownID else { return nil }
            return base.whereField("studentID", isEqualTo: ownID)
        }
        let teacherScoped = base.whereField("teacherID", isEqualTo: user.uid)
        guard let studentID else { return teacherScoped }
        return teacherScoped.whereField("studentID", isEqualTo: studentID)
    }

    private func requireScopedQuery(studentID: String? = nil) throws -> Query {
        guard let query = scopedQuery(studentID: studentID) else {
            throw SubmissionRepositoryError.notSignedIn
        }
        return query
    }

    // MARK: - Real-time Listeners

    /// Listen for all submissions within an assignment (teacher view).
    func startListening(assignmentID: String) {
        listener?.remove()
        listener = nil
        guard let query = scopedQuery()?.whereField("assignmentID", isEqualTo: assignmentID) else {
            submissions = []
            return
        }
        listener = firebase.addQueryListener(query, label: collectionPath) { [weak self] (submissions: [Submission]) in
            self?.submissions = submissions.sorted { $0.timestamp > $1.timestamp }
        }
    }

    /// Listen for all recent submissions across the teacher's active
    /// assignments. Powers `SubmissionInboxView_macOS` and
    /// `SubmissionInboxView_iOS`.
    ///
    /// Firestore caps `whereField(_:in:)` at 30 values. We fan out one
    /// listener per chunk and merge results keyed by submissionID, so a
    /// teacher with many assignments still sees every submission live
    /// (ISSUE-005).
    func startListeningForTeacher(classAssignmentIDs: [String]) {
        // Tear down anything from a previous run (single or multi-chunk).
        listener?.remove()
        listener = nil
        teacherChunkListeners.forEach { $0.remove() }
        teacherChunkListeners = []
        teacherChunkResults = [:]

        guard !classAssignmentIDs.isEmpty, let scoped = scopedQuery() else {
            submissions = []
            return
        }

        let chunks = classAssignmentIDs.chunked(into: 30)
        for (index, chunk) in chunks.enumerated() {
            let query = scoped
                .whereField("assignmentID", in: chunk)
                .order(by: "timestamp", descending: true)
                .limit(to: 100)

            let registration = query.addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error = error {
                    print("Erreur écoute soumissions enseignant (chunk \(index)): \(error.localizedDescription)")
                    self.teacherChunkResults[index] = []
                    self.recomputeMergedTeacherSubmissions()
                    return
                }
                guard let documents = snapshot?.documents else {
                    self.teacherChunkResults[index] = []
                    self.recomputeMergedTeacherSubmissions()
                    return
                }
                do {
                    let parsed = try documents.map { try $0.data(as: Submission.self) }
                    self.teacherChunkResults[index] = parsed
                } catch {
                    print("Erreur décodage soumissions enseignant (chunk \(index)): \(error.localizedDescription)")
                    self.teacherChunkResults[index] = []
                }
                self.recomputeMergedTeacherSubmissions()
            }
            teacherChunkListeners.append(registration)
        }
    }

    /// Merge per-chunk submission results into a single ordered list,
    /// deduplicated by submissionID.
    private func recomputeMergedTeacherSubmissions() {
        var seen: Set<String> = []
        var merged: [Submission] = []
        for chunkResults in teacherChunkResults.values {
            for submission in chunkResults {
                guard let id = submission.id else { continue }
                if seen.insert(id).inserted {
                    merged.append(submission)
                }
            }
        }
        merged.sort { $0.timestamp > $1.timestamp }
        // Cap to 100 like the previous single-listener behaviour, post-merge,
        // so the inbox stays responsive when many assignments are active.
        submissions = Array(merged.prefix(100))
    }

    /// Listen for a student's submissions within an assignment.
    func startListening(studentID: String, assignmentID: String) {
        listener?.remove()
        listener = nil
        // Use a compound listener — Firestore requires a composite index for this
        guard let query = scopedQuery(studentID: studentID)?
            .whereField("assignmentID", isEqualTo: assignmentID) else {
            submissions = []
            return
        }
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
        teacherChunkListeners.forEach { $0.remove() }
        teacherChunkListeners = []
        teacherChunkResults = [:]
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
        try await firebase.getDocuments(
            matching: requireScopedQuery().whereField("exerciseID", isEqualTo: exerciseID)
        )
    }

    /// Get all submissions by a student.
    func getSubmissions(studentID: String) async throws -> [Submission] {
        try await firebase.getDocuments(matching: requireScopedQuery(studentID: studentID))
    }

    /// Get all submissions for an assignment (a student only gets their own).
    func getSubmissions(assignmentID: String) async throws -> [Submission] {
        try await firebase.getDocuments(
            matching: requireScopedQuery().whereField("assignmentID", isEqualTo: assignmentID)
        )
    }

    /// Get all submissions across a batch of assignment IDs in a single
    /// Firestore round-trip. The caller is responsible for keeping the input
    /// at or below the Firestore `in`-query cap (30 values) — typically by
    /// chunking. Used by `StatisticsView` to avoid the N round-trips it
    /// previously did per class change (ISSUE-014).
    func getSubmissions(inAssignments assignmentIDs: [String]) async throws -> [Submission] {
        guard !assignmentIDs.isEmpty else { return [] }
        precondition(
            assignmentIDs.count <= 30,
            "Firestore 'in' queries support at most 30 values — chunk first."
        )
        return try await firebase.getDocuments(
            matching: requireScopedQuery().whereField("assignmentID", in: assignmentIDs)
        )
    }

    /// Check if a student has already submitted for an exercise within an assignment.
    func getExistingSubmission(
        studentID: String,
        exerciseID: String,
        assignmentID: String,
        attemptNumber: Int
    ) async throws -> Submission? {
        let query = try requireScopedQuery(studentID: studentID)
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

// MARK: - Errors

enum SubmissionRepositoryError: LocalizedError {
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Session expirée. Reconnectez-vous."
        }
    }
}
