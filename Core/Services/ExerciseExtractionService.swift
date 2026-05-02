//
//  ExerciseExtractionService.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import FirebaseFunctions

/// Service for extracting LaTeX from exercise images via Cloud Functions.
/// Calls the `extract_exercise` Cloud Function which uses Claude Haiku 4.5 Vision
/// to convert a photographed/scanned exercise into structured LaTeX.
final class ExerciseExtractionService {

    static let shared = ExerciseExtractionService()

    private let functions = Functions.functions(region: "europe-west6")

    private init() {}

    /// Result of an extraction.
    struct ExtractionResult {
        let statement: String
        let expectedAnswer: String
    }

    /// Extracts the exercise statement and expected answer from an image
    /// stored at the given Cloud Storage path.
    ///
    /// - Parameter storagePath: The Cloud Storage path (e.g., "exercises/abc123.jpg")
    /// - Returns: An `ExtractionResult` with the extracted LaTeX content.
    /// - Throws: If the Cloud Function call fails or returns invalid data.
    func extractExercise(storagePath: String) async throws -> ExtractionResult {
        let data: [String: Any] = ["storagePath": storagePath]

        let result = try await functions.httpsCallable("extract_exercise").call(data)

        guard let dict = result.data as? [String: Any],
              let statement = dict["statement"] as? String,
              let expectedAnswer = dict["expectedAnswer"] as? String else {
            throw ExtractionError.invalidResponse
        }

        return ExtractionResult(
            statement: statement,
            expectedAnswer: expectedAnswer
        )
    }

    enum ExtractionError: LocalizedError {
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "La réponse du service d'extraction est invalide."
            }
        }
    }
}
