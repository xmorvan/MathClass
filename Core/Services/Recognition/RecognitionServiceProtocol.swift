//
//  RecognitionServiceProtocol.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation

/// Result of handwriting recognition.
struct RecognitionResult {
    /// The ordered LaTeX expressions for each step of the student's work.
    var latexSteps: [String]
    /// Confidence score from 0.0 to 1.0. Below 0.7 the student should be warned.
    var confidence: Double
}

/// Abstract protocol for handwriting recognition services.
/// Allows swapping between Claude Vision, Apple Vision, or mock implementations.
protocol RecognitionService {
    /// Recognize handwriting from a PNG image.
    /// - Parameter imageData: Raw PNG data of the student's PencilKit drawing.
    /// - Returns: A `RecognitionResult` with extracted LaTeX steps and confidence.
    /// - Throws: On network errors, API failures, or unparseable responses.
    func recognizeHandwriting(from imageData: Data) async throws -> RecognitionResult
}

/// Errors specific to recognition.
enum RecognitionError: LocalizedError {
    case noImageData
    case apiError(String)
    case invalidResponse
    /// Carries the steps that were read, so the student can check them.
    case lowConfidence(Double, steps: [String])

    var errorDescription: String? {
        switch self {
        case .noImageData:
            return "Aucun dessin à lire.".tr
        case .apiError(let message):
            // Server details ("INTERNAL", stack messages) mean nothing to a
            // student; keep them in the console only.
            print("RecognitionError.apiError: \(message)")
            return "La lecture de votre travail n'a pas abouti. Réessayez dans un instant.".tr
        case .invalidResponse:
            return "La lecture de votre travail n'a pas abouti. Réessayez dans un instant.".tr
        case .lowConfidence(let score, let steps):
            return LocalizationManager.shared.format(
                steps.isEmpty
                    ? "Écriture difficile à lire (confiance %@ %%). Réécrivez plus lisiblement."
                    : "Écriture difficile à lire (confiance %@ %%). Vérifiez bien chaque étape, ou réécrivez plus lisiblement.",
                String(Int((score * 100).rounded()))
            )
        }
    }
}
