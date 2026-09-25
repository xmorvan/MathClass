//
//  SessionRepository.swift
//  MathClass
//
//  CRUD + listener for sessions under a period. Sessions own their own
//  exercise roster (subcollection: `exercises/`).
//

import Foundation
import FirebaseFirestore
import Combine

@MainActor
final class SessionRepository: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var sessionExercises: [String: [AssignmentExercise]] = [:]
    @Published private(set) var isLoading: Bool = false
    @Published var error: String?

    private let firebase = FirebaseService.shared
    private var sessionsListener: ListenerRegistration?
    private var exercisesListeners: [String: ListenerRegistration] = [:]

    deinit {
        sessionsListener?.remove()
        for (_, listener) in exercisesListeners {
            listener.remove()
        }
    }

    private func sessionsCollectionPath(periodID: String) -> String {
        "periods/\(periodID)/sessions"
    }

    private func exercisesCollectionPath(periodID: String, sessionID: String) -> String {
        "periods/\(periodID)/sessions/\(sessionID)/exercises"
    }

    /// Listen for sessions of a single period.
    func startListening(periodID: String) {
        sessionsListener?.remove()
        sessionsListener = firebase.addCollectionListener(
            collection: sessionsCollectionPath(periodID: periodID)
        ) { [weak self] (sessions: [Session]) in
            self?.sessions = sessions.sorted { $0.order < $1.order }
            self?.refreshExerciseListeners(periodID: periodID, sessions: sessions)
        }
    }

    private func refreshExerciseListeners(periodID: String, sessions: [Session]) {
        // Tear down stale listeners for sessions that no longer exist.
        let currentIDs = Set(sessions.compactMap { $0.id })
        for (sid, listener) in exercisesListeners where !currentIDs.contains(sid) {
            listener.remove()
            exercisesListeners.removeValue(forKey: sid)
            sessionExercises.removeValue(forKey: sid)
        }
        // Open listeners for any new sessions.
        for session in sessions {
            guard let sid = session.id, exercisesListeners[sid] == nil else { continue }
            let path = exercisesCollectionPath(periodID: periodID, sessionID: sid)
            exercisesListeners[sid] = firebase.addCollectionListener(collection: path) { [weak self] (exercises: [AssignmentExercise]) in
                self?.sessionExercises[sid] = exercises.sorted { $0.order < $1.order }
            }
        }
    }

    func stopListening() {
        sessionsListener?.remove()
        sessionsListener = nil
        for (_, listener) in exercisesListeners {
            listener.remove()
        }
        exercisesListeners.removeAll()
        sessions = []
        sessionExercises = [:]
    }

    func createSession(_ session: Session) async throws -> String {
        let ref = try await firebase.createDocument(
            session,
            in: sessionsCollectionPath(periodID: session.periodID)
        )
        return ref.documentID
    }

    func updateSession(_ session: Session) async throws {
        guard let id = session.id else { return }
        try await firebase.updateDocument(
            session,
            in: sessionsCollectionPath(periodID: session.periodID),
            documentID: id
        )
    }

    func deleteSession(id: String, periodID: String) async throws {
        try await firebase.deleteDocument(
            from: sessionsCollectionPath(periodID: periodID),
            documentID: id
        )
    }

    // MARK: - Exercises within a session

    func addExercise(_ ae: AssignmentExercise, to sessionID: String, periodID: String) async throws -> String {
        var copy = ae
        copy.assignmentID = sessionID  // reuse the field as session ID for code reuse
        let ref = try await firebase.createDocument(
            copy,
            in: exercisesCollectionPath(periodID: periodID, sessionID: sessionID)
        )
        return ref.documentID
    }

    func updateExercise(_ ae: AssignmentExercise, in sessionID: String, periodID: String) async throws {
        guard let id = ae.id else { return }
        try await firebase.updateDocument(
            ae,
            in: exercisesCollectionPath(periodID: periodID, sessionID: sessionID),
            documentID: id
        )
    }

    func removeExercise(id: String, from sessionID: String, periodID: String) async throws {
        try await firebase.deleteDocument(
            from: exercisesCollectionPath(periodID: periodID, sessionID: sessionID),
            documentID: id
        )
    }

    /// Append additional exercises into a session targeted at a specific
    /// student. Used by the live dashboard's "push more exercises" action
    /// when a student finishes ahead of the rest of the class. Each new
    /// `AssignmentExercise` carries `targetStudentIDs == [studentID]` so
    /// only that student picks them up.
    ///
    /// Order numbers are appended after the current max so the existing
    /// roster's ordering is preserved.
    func appendExercises(
        exerciseIDs: [String],
        forStudentID studentID: String,
        periodID: String,
        sessionID: String
    ) async throws {
        guard !exerciseIDs.isEmpty else { return }
        let existing = sessionExercises[sessionID] ?? []
        let nextOrder = (existing.map(\.order).max() ?? -1) + 1
        var batch: [AssignmentExercise] = []
        for (offset, exerciseID) in exerciseIDs.enumerated() {
            batch.append(AssignmentExercise(
                assignmentID: sessionID,
                exerciseID: exerciseID,
                order: nextOrder + offset,
                targetStudentIDs: [studentID],
                targetGroupName: nil,
                targetGroupID: nil
            ))
        }
        try await firebase.createDocuments(
            batch,
            in: exercisesCollectionPath(periodID: periodID, sessionID: sessionID),
            idFor: { $0.id }
        )
    }

    /// Returns the exercise list a single student should see for the given
    /// session, ordered. A student gets:
    ///   • exercises with no targeting (everyone),
    ///   • exercises explicitly targeting the student,
    ///   • exercises targeting a group the student belongs to.
    func exercisesForStudent(
        studentID: String,
        groupID: String?,
        in sessionID: String
    ) -> [AssignmentExercise] {
        let all = sessionExercises[sessionID] ?? []
        return all.filter { ae in
            let targetsByID = ae.targetStudentIDs?.isEmpty == false
            let targetsByGroup = ae.targetGroupID != nil
            if !targetsByID && !targetsByGroup {
                return true
            }
            if let targets = ae.targetStudentIDs, targets.contains(studentID) {
                return true
            }
            if let target = ae.targetGroupID, let gid = groupID, target == gid {
                return true
            }
            return false
        }
    }
}
