//
//  Exercise.swift
//  MathClass
//
//  Created by Xavier Morvan on 22.01.2025.
//

import Foundation
import FirebaseFirestore

/// Represents a math exercise created by a teacher.
/// Exercises are top-level Firestore documents at `exercises/{exerciseID}`
/// to allow cross-class queries if needed later.
struct Exercise: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var title: String
    /// The exercise statement as LaTeX/text content
    var statement: String
    /// Cloud Storage URL to an image of the exercise (for image-based creation)
    var statementImageURL: String?
    /// The expected answer as a LaTeX expression
    var expectedAnswer: String
    /// Reference to the chapter this exercise belongs to
    var chapterID: String?
    /// References to competencies this exercise tests
    var competencyIDs: [String]
    /// Difficulty level from 1 (easy) to 5 (hard), used for the "levels" mode
    var difficultyLevel: Int
    /// How this exercise was created
    var creationMethod: ExerciseCreationMethod
    /// The teacher who created this exercise
    var teacherID: String
    /// When this exercise was created
    var createdAt: Date


    /// Title without LaTeX markup ("Résoudre $4x + 2 = 18$" → "Résoudre
    /// 4x + 2 = 18"), for lists and headers.
    var displayTitle: String { title.latexPlainPreview }
    init(
        id: String? = nil,
        title: String,
        statement: String,
        statementImageURL: String? = nil,
        expectedAnswer: String = "",
        chapterID: String? = nil,
        competencyIDs: [String] = [],
        difficultyLevel: Int = 1,
        creationMethod: ExerciseCreationMethod = .wysiwyg,
        teacherID: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.statement = statement
        self.statementImageURL = statementImageURL
        self.expectedAnswer = expectedAnswer
        self.chapterID = chapterID
        self.competencyIDs = competencyIDs
        self.difficultyLevel = max(1, min(5, difficultyLevel))
        self.creationMethod = creationMethod
        self.teacherID = teacherID
        self.createdAt = createdAt
    }
}
