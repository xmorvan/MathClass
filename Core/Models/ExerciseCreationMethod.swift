//
//  ExerciseCreationMethod.swift
//  MathClass
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation

/// How the exercise was created.
enum ExerciseCreationMethod: String, Codable, Hashable {
    /// Created from an imported image (photo/scan) with AI extraction
    case image
    /// Created using the WYSIWYG LaTeX editor
    case wysiwyg
}
