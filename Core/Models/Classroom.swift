//
//  Classroom.swift
//  MathClass
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import FirebaseFirestore

/// Represents a classroom managed by a teacher.
/// Stored in Firestore at `classes/{classID}`.
/// Students and chapters are in subcollections within the class document.
struct ClassRoom: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    /// Display name (e.g., "3ème A", "Terminale S2")
    var name: String
    /// Unique class code for student onboarding (format: MX-XXXX)
    var classCode: String
    /// The teacher who owns this class
    var teacherID: String
    /// When this class was created (optional for legacy documents)
    var createdAt: Date?
    /// Notation strictness setting. Default = `true` (strict). When strict
    /// the AI surfaces notation issues separately and never converts a
    /// notation problem into a wrong-answer verdict. Stored as optional
    /// to keep legacy class documents (without the field) decodable.
    var notationStrict: Bool?

    /// Effective strict-notation flag that defaults to `true` for legacy
    /// classes that don't carry the field yet.
    var isNotationStrict: Bool {
        notationStrict ?? true
    }

    init(
        id: String? = nil,
        name: String,
        classCode: String,
        teacherID: String,
        createdAt: Date? = Date(),
        notationStrict: Bool? = true
    ) {
        self.id = id
        self.name = name
        self.classCode = classCode
        self.teacherID = teacherID
        self.createdAt = createdAt
        self.notationStrict = notationStrict
    }
}
