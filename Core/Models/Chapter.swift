//
//  Chapter.swift
//  MathClass
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import FirebaseFirestore

/// Represents a chapter within a classroom (e.g., "Equations", "Functions", "Geometry").
/// Stored in Firestore at `classes/{classID}/chapters/{chapterID}`.
struct Chapter: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var name: String
    var order: Int
    var classID: String

    init(
        id: String? = nil,
        name: String,
        order: Int,
        classID: String
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.classID = classID
    }
}
