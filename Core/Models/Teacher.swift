//
//  Teacher.swift
//  MathClass
//
//  Created by Xavier Morvan on 19.03.2026.
//

import Foundation
import FirebaseFirestore

/// Represents a teacher's profile data.
/// Stored in Firestore at `users/{teacherID}`.
struct Teacher: Identifiable, Codable {
    @DocumentID var id: String?
    var email: String
    var firstName: String
    var lastName: String
    var role: String
    var createdAt: Date

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    /// Initials for avatar display (e.g., "XM")
    var initials: String {
        let first = firstName.first.map(String.init) ?? ""
        let last = lastName.first.map(String.init) ?? ""
        return "\(first)\(last)".uppercased()
    }
}
