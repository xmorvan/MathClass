//
//  Session.swift
//  MathClass
//
//  A `Session` is one slot inside a `Period` — a contiguous block of
//  exercises with a single correction mode and ordering rule. Each
//  session carries its own per-student / per-group exercise list (the
//  `assignmentExercises` subcollection — kept name for migration
//  compatibility with the legacy flat `Assignment` model).
//
//  Path: `periods/{periodID}/sessions/{sessionID}`
//        `periods/{periodID}/sessions/{sessionID}/exercises/{aeID}`
//

import Foundation
import FirebaseFirestore

struct Session: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    /// Parent period ID.
    var periodID: String
    /// Order within the period (0-indexed).
    var order: Int
    /// Display label (e.g. "Révision algèbre", "Défi géométrie")
    var name: String
    /// Correction mode: differentiation / levels / evaluation. The same
    /// enum that legacy `Assignment` used.
    var mode: AssignmentMode
    /// When `true`, the student picks any available exercise rather
    /// than being forced through them in order.
    var allowFreeOrder: Bool
    /// Whether this session is the currently-running one in the period.
    /// Only one session per period should be active at a time.
    var isActive: Bool
    /// When this session was created.
    var createdAt: Date

    init(
        id: String? = nil,
        periodID: String,
        order: Int,
        name: String,
        mode: AssignmentMode,
        allowFreeOrder: Bool = false,
        isActive: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.periodID = periodID
        self.order = order
        self.name = name
        self.mode = mode
        self.allowFreeOrder = allowFreeOrder
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
