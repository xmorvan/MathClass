//
//  Competency.swift
//  MathClass
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import FirebaseFirestore

/// Represents a competency within a chapter (e.g., "Solve a first-degree equation").
/// Stored in Firestore at `classes/{classID}/chapters/{chapterID}/competencies/{competencyID}`.
struct Competency: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var label: String
    var chapterID: String

    init(
        id: String? = nil,
        label: String,
        chapterID: String
    ) {
        self.id = id
        self.label = label
        self.chapterID = chapterID
    }
}
