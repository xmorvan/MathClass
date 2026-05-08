//
//  Period.swift
//  MathClass
//
//  A "period" represents one class hour planned by the teacher. It contains
//  one or more `Session` documents (subcollection). Different students in
//  the same class can follow different session sequences within a period —
//  that's the differentiation feature. Theory delivery is out of MVP scope,
//  so all sessions in MVP are exercise sessions.
//
//  Path: `periods/{periodID}` (top-level for cross-class queries)
//        `periods/{periodID}/sessions/{sessionID}`
//

import Foundation
import FirebaseFirestore

struct Period: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    /// The class this period belongs to.
    var classID: String
    /// Display name (e.g. "Cours 9 nov", "Mardi matin")
    var name: String
    /// When the period starts (used by the live dashboard to know what's
    /// active "right now").
    var startTime: Date
    /// When the period ends.
    var endTime: Date
    /// Whether the teacher has launched this period to students. Students
    /// only see active periods.
    var isActive: Bool
    /// When the period was created.
    var createdAt: Date

    init(
        id: String? = nil,
        classID: String,
        name: String,
        startTime: Date,
        endTime: Date,
        isActive: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.classID = classID
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
