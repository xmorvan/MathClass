//
//  Student.swift
//  MathClass
//
//  Created by Xavier Morvan on 22.01.2025.
//

import Foundation
import FirebaseFirestore

/// Represents a student within a classroom.
/// Stored in Firestore at `classes/{classID}/students/{studentID}`.
struct Student: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var firstName: String
    var lastName: String
    var classID: String?
    /// Device token set when the student links their iPad to their identity.
    /// Used to identify which device is linked to which student.
    var deviceToken: String?
    /// Teacher-assigned baseline level on a 1–5 scale used by the
    /// differentiation flow. `nil` means the teacher hasn't set one yet.
    var level: Int?
    /// Optional group membership — references a `Group.id` under the
    /// same class. Students can be in at most one group at a time.
    var groupID: String?

    /// Full display name (prénom nom)
    var fullName: String {
        "\(firstName) \(lastName)"
    }

    /// Display name for lists (nom, prénom)
    var sortName: String {
        "\(lastName), \(firstName)"
    }

    /// Returns the level clamped to 1...5, or `nil` if unset.
    var clampedLevel: Int? {
        level.map { max(1, min(5, $0)) }
    }

    init(
        id: String? = nil,
        firstName: String,
        lastName: String,
        classID: String? = nil,
        deviceToken: String? = nil,
        level: Int? = nil,
        groupID: String? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.classID = classID
        self.deviceToken = deviceToken
        self.level = level.map { max(1, min(5, $0)) }
        self.groupID = groupID
    }
}
