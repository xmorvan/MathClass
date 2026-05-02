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
    case lowConfidence(Double)

    var errorDescription: String? {
        switch self {
        case .noImageData:
            return "Aucune donnée d'image fournie."
        case .apiError(let message):
            return "Erreur API de reconnaissance: \(message)"
        case .invalidResponse:
            return "La réponse de la reconnaissance est invalide."
        case .lowConfidence(let score):
            return String(format: "Confiance faible (%.0f%%). Veuillez réécrire plus lisiblement.", score * 100)
        }
    }
}
