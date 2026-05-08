//
//  Group.swift
//  MathClass
//
//  A named subset of students within a class. Used by the differentiation
//  flow so a teacher can target an exercise list at a group rather than
//  individuals.
//

import Foundation
import FirebaseFirestore

/// A named group of students within a single class.
/// Stored at `classes/{classID}/groups/{groupID}`.
struct StudentGroup: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    /// Display name set by the teacher (e.g. "Group A", "Renforcement")
    var name: String
    /// The class this group belongs to.
    var classID: String
    /// Member student IDs. Source of truth for membership; the optional
    /// `Student.groupID` denormalization mirrors this for query convenience.
    var studentIDs: [String]
    /// When this group was created.
    var createdAt: Date

    init(
        id: String? = nil,
        name: String,
        classID: String,
        studentIDs: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.classID = classID
        self.studentIDs = studentIDs
        self.createdAt = createdAt
    }
}
