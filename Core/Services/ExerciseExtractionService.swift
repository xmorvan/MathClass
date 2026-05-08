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
        /// IDs of competencies the AI suggests for this exercise.
        /// Always a subset of the catalog passed in the request.
        let suggestedCompetencyIDs: [String]
    }

    /// A single entry of the teacher's competency catalog passed to the
    /// Cloud Function so it can suggest relevant tags.
    struct CatalogEntry {
        let id: String
        let label: String
    }

    /// Extracts the exercise statement and expected answer from an image
    /// stored at the given Cloud Storage path. Optionally passes the
    /// teacher's competency catalog; when provided, the response includes
    /// up to 5 suggested competency IDs from that catalog.
    func extractExercise(
        storagePath: String,
        competencies: [CatalogEntry] = []
    ) async throws -> ExtractionResult {
        var data: [String: Any] = ["storagePath": storagePath]
        if !competencies.isEmpty {
            data["competencies"] = competencies.map { ["id": $0.id, "label": $0.label] }
        }

        let result = try await functions.httpsCallable("extract_exercise").call(data)

        guard let dict = result.data as? [String: Any],
              let statement = dict["statement"] as? String,
              let expectedAnswer = dict["expectedAnswer"] as? String else {
            throw ExtractionError.invalidResponse
        }

        let suggestedIDs = (dict["competencyIDs"] as? [String]) ?? []

        let trimmedStatement = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAnswer = expectedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedStatement.isEmpty && trimmedAnswer.isEmpty {
            throw ExtractionError.empty
        }

        return ExtractionResult(
            statement: statement,
            expectedAnswer: expectedAnswer,
            suggestedCompetencyIDs: suggestedIDs
        )
    }

    enum ExtractionError: LocalizedError {
        case invalidResponse
        case empty

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "La réponse du service d'extraction est invalide."
            case .empty:
                return "Aucun contenu détecté — réessayez ou éditez manuellement."
            }
        }
    }
}
