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
/// 4. The Cloud Function persists `correctionResult` + `finalResult` on the
///    submission doc using the Admin SDK (firestore.rules block client-side
///    updates from students, who have no Firebase Auth — see ISSUE-040)
/// 5. Returns a `CorrectionResult` with per-step correctness and first error index
final class CorrectionService {

    static let shared = CorrectionService()

    private let functions = Functions.functions(region: "europe-west6")

    /// Timeout for the correction Cloud Function call (60 seconds — correction is slower)
    private let functionTimeout: TimeInterval = 60

    private init() {}

    /// Correct a student's submission and return the result.
    /// The Cloud Function also persists the result on the submission doc.
    ///
    /// - Parameters:
    ///   - submissionID: The Firestore document ID of the submission.
    ///   - studentSteps: The LaTeX steps confirmed by the student.
    ///   - expectedAnswer: The correct answer in LaTeX.
    ///   - statement: The exercise statement for context.
    ///   - attemptNumber: 1 or 2 (used to compute success_1st vs success_2nd).
    ///   - notationStrict: Class-level strictness flag. When `true`, the
    ///     server returns a separate `notationNote` for sloppy notation
    ///     without flipping the verdict.
    /// - Returns: A `CorrectionResult` with per-step booleans, first error
    ///   index, optional notation note, and optional per-step error tags.
    /// - Throws: `CorrectionServiceError` on failure.
    func correctSubmission(
        submissionID: String,
        studentSteps: [String],
        expectedAnswer: String,
        statement: String,
        attemptNumber: Int,
        notationStrict: Bool = true
    ) async throws -> CorrectionResult {
        guard !studentSteps.isEmpty else {
            return CorrectionResult(stepResults: [], firstErrorIndex: nil)
        }

        let data: [String: Any] = [
            "studentSteps": studentSteps,
            "expectedAnswer": expectedAnswer,
            "statement": statement,
            "submissionID": submissionID,
            "attemptNumber": attemptNumber,
            "notationStrict": notationStrict
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
            let notationNote = (dict["notationNote"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let errorTagsRaw = dict["errorTags"] as? [Any]
            let errorTags: [String?]? = errorTagsRaw?.map { $0 as? String }

            return CorrectionResult(
                stepResults: stepResults,
                firstErrorIndex: firstErrorIndex,
                notationNote: notationNote,
                errorTags: errorTags
            )
        } catch let error as CorrectionServiceError {
            throw error
        } catch {
            throw CorrectionServiceError.apiError(error.localizedDescription)
        }
    }

    /// Correct a submission and return both the per-step result and the
    /// derived final outcome. The Firestore persistence happens server-side
    /// inside the Cloud Function (Admin SDK) — the client computes the same
    /// `finalResult` locally so the UI can render feedback before the
    /// teacher's submissions listener round-trips.
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
        attemptNumber: Int,
        notationStrict: Bool = true
    ) async throws -> (CorrectionResult, SubmissionResult) {
        guard !submissionID.isEmpty else {
            throw CorrectionServiceError.noSubmissionID
        }

        let correctionResult = try await correctSubmission(
            submissionID: submissionID,
            studentSteps: studentSteps,
            expectedAnswer: expectedAnswer,
            statement: statement,
            attemptNumber: attemptNumber,
            notationStrict: notationStrict
        )

        let allCorrect = correctionResult.stepResults.allSatisfy { $0 }
        let finalResult: SubmissionResult = allCorrect
            ? (attemptNumber == 1 ? .success1st : .success2nd)
            : .failed

        return (correctionResult, finalResult)
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
