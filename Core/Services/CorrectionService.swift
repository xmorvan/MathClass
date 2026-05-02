//
//  CorrectionService.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import FirebaseFunctions

/// Service for correcting student submissions via the hybrid Claude + SymPy Cloud Function.
///
/// Flow:
/// 1. Receives student LaTeX steps, expected answer, and exercise statement
/// 2. Calls the `correct_submission` Cloud Function
/// 3. The Cloud Function uses Claude to structure step pairs, SymPy for algebraic verification
/// 4. Returns a `CorrectionResult` with per-step correctness and first error index
/// 5. Optionally updates the Submission document in Firestore via FirebaseService
final class CorrectionService {

    static let shared = CorrectionService()

    private let functions = Functions.functions(region: "europe-west6")
    // Per CLAUDE.md, all Firestore writes must go through FirebaseService.
    // The previous `private let db = Firestore.firestore()` violated that.
    private let firebase = FirebaseService.shared

    /// Timeout for the correction Cloud Function call (60 seconds — correction is slower)
    private let functionTimeout: TimeInterval = 60

    private init() {}

    /// Correct a student's submission and return the result.
    ///
    /// - Parameters:
    ///   - studentSteps: The LaTeX steps confirmed by the student.
    ///   - expectedAnswer: The correct answer in LaTeX.
    ///   - statement: The exercise statement for context.
    /// - Returns: A `CorrectionResult` with per-step booleans and first error index.
    /// - Throws: `CorrectionServiceError` on failure.
    func correctSubmission(
        studentSteps: [String],
        expectedAnswer: String,
        statement: String
    ) async throws -> CorrectionResult {
        guard !studentSteps.isEmpty else {
            return CorrectionResult(stepResults: [], firstErrorIndex: nil)
        }

        let data: [String: Any] = [
            "studentSteps": studentSteps,
            "expectedAnswer": expectedAnswer,
            "statement": statement
        ]

        do {
            let callable = functions.httpsCallable("correct_submission")
            callable.timeoutInterval = functionTimeout

            let result = try await callable.call(data)

            guard let dict = result.data as? [String: Any] else {
                throw CorrectionServiceError.invalidResponse
            }

            guard let stepResults = dict["stepResults"] as? [Bool] else {
                throw CorrectionServiceError.invalidResponse
            }

            let firstErrorIndex = dict["firstErrorIndex"] as? Int

            return CorrectionResult(
                stepResults: stepResults,
                firstErrorIndex: firstErrorIndex
            )
        } catch let error as CorrectionServiceError {
            throw error
        } catch {
            throw CorrectionServiceError.apiError(error.localizedDescription)
        }
    }

    /// Correct a submission and update the Firestore document with the result.
    ///
    /// - Parameters:
    ///   - submissionID: The Firestore document ID of the submission.
    ///   - studentSteps: The LaTeX steps confirmed by the student.
    ///   - expectedAnswer: The correct answer in LaTeX.
    ///   - statement: The exercise statement for context.
    ///   - attemptNumber: The current attempt (1 or 2).
    /// - Returns: A tuple of `(CorrectionResult, SubmissionResult)`.
    /// - Throws: `CorrectionServiceError` on failure.
    func correctAndUpdate(
        submissionID: String,
        studentSteps: [String],
        expectedAnswer: String,
        statement: String,
        attemptNumber: Int
    ) async throws -> (CorrectionResult, SubmissionResult) {
        guard !submissionID.isEmpty else {
            throw CorrectionServiceError.noSubmissionID
        }

        // Get correction result
        let correctionResult = try await correctSubmission(
            studentSteps: studentSteps,
            expectedAnswer: expectedAnswer,
            statement: statement
        )

        // Determine final result based on correction and attempt
        let allCorrect = correctionResult.stepResults.allSatisfy { $0 }
        let finalResult: SubmissionResult = allCorrect
            ? (attemptNumber == 1 ? .success1st : .success2nd)
            : .failed
        // Note: if attemptNumber == 1 and mode allows 2nd chance, the
        // SubmissionViewModel will offer retry. We still record .failed for
        // this attempt — the 2nd attempt creates a new submission row.

        // Update Firestore submission document via FirebaseService (per
        // CLAUDE.md: never call `Firestore.firestore()` directly).
        let patch = SubmissionPatch(
            correctionResult: CorrectionResultPatch(
                stepResults: correctionResult.stepResults,
                firstErrorIndex: correctionResult.firstErrorIndex
            ),
            finalResult: finalResult.rawValue
        )
        try await firebase.updateDocument(patch, in: "submissions", documentID: submissionID)

        return (correctionResult, finalResult)
    }

    // MARK: - Encodable patch types

    /// Encodable shape for the partial-update payload — keeps the call site
    /// type-safe and avoids passing `[String: Any]` through the gateway.
    private struct SubmissionPatch: Encodable {
        let correctionResult: CorrectionResultPatch
        let finalResult: String
    }

    private struct CorrectionResultPatch: Encodable {
        let stepResults: [Bool]
        let firstErrorIndex: Int?
    }
}

// MARK: - Errors

enum CorrectionServiceError: LocalizedError {
    case invalidResponse
    case apiError(String)
    case noSubmissionID

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "La réponse du service de correction est invalide."
        case .apiError(let message):
            return "Erreur du service de correction: \(message)"
        case .noSubmissionID:
            return "Identifiant de soumission manquant."
        }
    }
}
