//
//  Assignment.swift
//  MathClass
//
//  Created by Xavier Morvan on 22.01.2025.
//

import Foundation
import FirebaseFirestore

/// Represents an assignment (a set of exercises assigned to a class).
/// Stored in Firestore at `assignments/{assignmentID}`.
/// Exercises within this assignment are in the subcollection
/// `assignments/{assignmentID}/exercises/{assignmentExerciseID}`.
struct Assignment: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    /// The class this assignment is for
    var classID: String
    /// The assignment mode determines feedback, 2nd chance, and progression rules
    var mode: AssignmentMode
    /// Whether the assignment is currently active for students
    var isActive: Bool
    /// When the assignment was created
    var createdAt: Date

    init(
        id: String? = nil,
        classID: String,
        mode: AssignmentMode,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.classID = classID
        self.mode = mode
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
