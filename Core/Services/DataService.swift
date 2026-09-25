//
//  DataService.swift
//  MathClass
//
//  Created by Xavier Morvan on 22.01.2025.
//

import Foundation
import FirebaseFirestore
import FirebaseStorage

/// Thin coordinator that holds references to entity-specific repositories.
/// Injected via SwiftUI environment to provide data access throughout the app.
///
/// The old DataService was a monolith that owned a single `Classroom` aggregate
/// and managed all Firestore operations. The new architecture delegates all CRUD
/// and listener management to dedicated repositories.
@MainActor
class DataService: ObservableObject {
    static let shared = DataService()

    // MARK: - Repositories

    let teacherRepository = TeacherRepository()
    let classRepository = ClassRepository()
    let studentRepository = StudentRepository()
    let exerciseRepository = ExerciseRepository()
    let chapterRepository = ChapterRepository()
    let assignmentRepository = AssignmentRepository()
    let submissionRepository = SubmissionRepository()
    let groupRepository = GroupRepository()
    let periodRepository = PeriodRepository()
    let sessionRepository = SessionRepository()

    // MARK: - Storage

    let storage = Storage.storage()

    private init() {}

    // MARK: - Convenience Methods

    /// Upload data to Cloud Storage and return the download path.
    func uploadData(_ data: Data, path: String) async throws -> String {
        let ref = storage.reference().child(path)
        // storage.rules only accept `image/*` uploads; without an explicit
        // content type the SDK sends application/octet-stream and every
        // drawing / exercise photo upload is rejected.
        let metadata = StorageMetadata()
        metadata.contentType = Self.contentType(forPath: path)
        _ = try await ref.putDataAsync(data, metadata: metadata)
        return path
    }

    private static func contentType(forPath path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "heic": return "image/heic"
        case "gif": return "image/gif"
        default: return "image/png"
        }
    }

    /// Download data from Cloud Storage.
    func downloadData(path: String, maxSize: Int64 = 10 * 1024 * 1024) async throws -> Data {
        let ref = storage.reference().child(path)
        return try await ref.data(maxSize: maxSize)
    }

    /// Get a download URL for a Cloud Storage path.
    func getDownloadURL(path: String) async throws -> URL {
        let ref = storage.reference().child(path)
        return try await ref.downloadURL()
    }
}
