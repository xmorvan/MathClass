//
//  AssignmentExercise.swift
//  MathClass
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import FirebaseFirestore

/// Links an assignment to an exercise, with ordering and targeting information.
/// Stored in Firestore at `assignments/{assignmentID}/exercises/{assignmentExerciseID}`.
struct AssignmentExercise: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var assignmentID: String
    var exerciseID: String
    var order: Int
    /// If nil, the exercise is assigned to all students in the class.
    /// If set, only these students receive this exercise (for differentiation mode).
    var targetStudentIDs: [String]?
    /// Optional group label for differentiation mode (e.g., "Groupe A").
    var targetGroupName: String?

    init(
        id: String? = nil,
        assignmentID: String,
        exerciseID: String,
        order: Int,
        targetStudentIDs: [String]? = nil,
        targetGroupName: String? = nil
    ) {
        self.id = id
        self.assignmentID = assignmentID
        self.exerciseID = exerciseID
        self.order = order
        self.targetStudentIDs = targetStudentIDs
        self.targetGroupName = targetGroupName
    }
}
