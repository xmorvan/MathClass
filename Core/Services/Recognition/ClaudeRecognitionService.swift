//
//  ClaudeRecognitionService.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import FirebaseFunctions

/// MVP implementation of `RecognitionService` using Claude Haiku 4.5 Vision via a Cloud Function.
///
/// Flow:
/// 1. Receives PNG data of the student's PencilKit drawing
/// 2. The PNG is already uploaded to Cloud Storage by SubmissionViewModel
/// 3. Calls the `recognize_handwriting` Cloud Function with the storage path
/// 4. The Cloud Function sends the image to Claude Haiku 4.5 Vision
/// 5. Returns structured LaTeX steps and a confidence score
final class ClaudeRecognitionService: RecognitionService {

    static let shared = ClaudeRecognitionService()

    private let functions = Functions.functions(region: "europe-west6")

    /// Timeout for the recognition Cloud Function call (30 seconds)
    private let functionTimeout: TimeInterval = 30

    private init() {}

    /// Recognize handwriting from a PNG image stored in Cloud Storage.
    ///
    /// - Parameter imageData: Raw PNG data of the student's drawing.
    ///   Note: In this implementation, `imageData` is not sent directly.
    ///   The PNG must already be uploaded to Cloud Storage. Use `recognizeFromStorage(path:)` instead
    ///   for the primary flow, or this method with a storage path embedded in the data.
    /// - Returns: A `RecognitionResult` with extracted LaTeX steps and confidence.
    /// - Throws: `RecognitionError` on failure.
    func recognizeHandwriting(from imageData: Data) async throws -> RecognitionResult {
        guard !imageData.isEmpty else {
            throw RecognitionError.noImageData
        }

        // Encode as base64 for direct send (fallback path)
        let base64Image = imageData.base64EncodedString()
        let data: [String: Any] = [
            "imageBase64": base64Image,
            "format": "png"
        ]

        return try await callRecognitionFunction(with: data)
    }

    /// Recognize handwriting from a PNG already uploaded to Cloud Storage.
    /// This is the primary flow used by SubmissionViewModel.
    ///
    /// - Parameter path: Cloud Storage path to the PNG (e.g., "submissions/class1/student123/exercise456_attempt1.png")
    /// - Returns: A `RecognitionResult` with extracted LaTeX steps and confidence.
    /// - Throws: `RecognitionError` on failure.
    func recognizeFromStorage(path: String) async throws -> RecognitionResult {
        guard !path.isEmpty else {
            throw RecognitionError.noImageData
        }

        let data: [String: Any] = [
            "storagePath": path,
            "format": "png"
        ]

        return try await callRecognitionFunction(with: data)
    }

    // MARK: - Private

    private func callRecognitionFunction(with data: [String: Any]) async throws -> RecognitionResult {
        do {
            let callable = functions.httpsCallable("recognize_handwriting")
            callable.timeoutInterval = functionTimeout

            let result = try await callable.call(data)

            guard let dict = result.data as? [String: Any] else {
                throw RecognitionError.invalidResponse
            }

            guard let steps = dict["steps"] as? [String] else {
                throw RecognitionError.invalidResponse
            }

            let confidence = dict["confidence"] as? Double ?? 0.0

            // Warn if confidence is too low. The previous `&& confidence > 0`
            // clause silently swallowed the case where Claude returned 0.0
            // (image unreadable / blank), which dumped the student into
            // VerificationView with an empty step list and no warning.
            if confidence < 0.7 {
                throw RecognitionError.lowConfidence(confidence)
            }

            return RecognitionResult(
                latexSteps: steps,
                confidence: confidence
            )
        } catch let error as RecognitionError {
            throw error
        } catch {
            throw RecognitionError.apiError(error.localizedDescription)
        }
    }
}
