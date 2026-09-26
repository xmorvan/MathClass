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
    /// When `true`, the student picks any available exercise rather than
    /// being forced through them in order. Mirrors `Session.allowFreeOrder`
    /// for the legacy flat-assignment path so the iPad student VM can react
    /// without reading the new Period/Session tree (ISSUE-014 §1.1).
    /// Optional in the JSON for backward compat with documents that
    /// pre-date this field — defaults to `false` (linear).
    var allowFreeOrder: Bool?
    /// Optional name given by the teacher ("Équations — révision").
    var name: String?

    init(
        id: String? = nil,
        classID: String,
        mode: AssignmentMode,
        isActive: Bool = true,
        createdAt: Date = Date(),
        allowFreeOrder: Bool? = nil,
        name: String? = nil
    ) {
        self.id = id
        self.classID = classID
        self.mode = mode
        self.isActive = isActive
        self.createdAt = createdAt
        self.allowFreeOrder = allowFreeOrder
        self.name = name
    }

    /// "Name · Mode" when named, the mode alone otherwise (students need
    /// the mode: it says whether they get feedback).
    var titleWithMode: String {
        displayTitle == mode.displayName ? mode.displayName : "\(displayTitle) · \(mode.displayName)"
    }

    /// The teacher's name for the assignment, or its mode when unnamed.
    var displayTitle: String {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return mode.displayName }
        return name
    }

    /// Resolved free-order flag (defaults to false for legacy docs).
    var isFreeOrder: Bool { allowFreeOrder ?? false }
}
