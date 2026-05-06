//
//  LevelProgressRepository.swift
//  MathClass
//

import Foundation
import FirebaseFirestore

/// Persists per-student / per-assignment levels-mode progress so it survives
/// app relaunch and re-login (ISSUE-008). Stored at
/// `classes/{classID}/students/{studentID}/levelProgress/{assignmentID}`.
///
/// Not `@MainActor` — this is a stateless service-style repo (no `@Published`
/// state to keep on the main thread), and being non-isolated lets it be used
/// as a `.shared` default-arg for ViewModel inits without Swift 6 warnings.
final class LevelProgressRepository {

    static let shared = LevelProgressRepository()

    private let firebase = FirebaseService.shared

    private init() {}

    private func collectionPath(classID: String, studentID: String) -> String {
        "classes/\(classID)/students/\(studentID)/levelProgress"
    }

    /// Persisted shape for a student's level progress on one assignment.
    struct LevelProgressDoc: Codable, Hashable {
        var consecutiveCorrect: Int
        var currentLevel: Int
        var updatedAt: Date

        init(
            consecutiveCorrect: Int = 0,
            currentLevel: Int = 1,
            updatedAt: Date = Date()
        ) {
            self.consecutiveCorrect = consecutiveCorrect
            self.currentLevel = currentLevel
            self.updatedAt = updatedAt
        }
    }

    func getProgress(
        classID: String,
        studentID: String,
        assignmentID: String
    ) async throws -> LevelProgressDoc? {
        let path = collectionPath(classID: classID, studentID: studentID)
        do {
            let doc: LevelProgressDoc = try await firebase.getDocument(assignmentID, from: path)
            return doc
        } catch let error as FirebaseServiceError {
            if case .documentNotFound = error { return nil }
            throw error
        }
    }

    func setProgress(
        classID: String,
        studentID: String,
        assignmentID: String,
        progress: LevelProgressDoc
    ) async throws {
        let path = collectionPath(classID: classID, studentID: studentID)
        _ = try await firebase.createDocument(
            progress,
            in: path,
            documentID: assignmentID
        )
    }
}
