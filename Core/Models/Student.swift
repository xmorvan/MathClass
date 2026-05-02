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

    /// Full display name (prénom nom)
    var fullName: String {
        "\(firstName) \(lastName)"
    }

    /// Display name for lists (nom, prénom)
    var sortName: String {
        "\(lastName), \(firstName)"
    }

    init(
        id: String? = nil,
        firstName: String,
        lastName: String,
        classID: String? = nil,
        deviceToken: String? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.classID = classID
        self.deviceToken = deviceToken
    }
}
