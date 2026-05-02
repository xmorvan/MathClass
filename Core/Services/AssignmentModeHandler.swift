//
//  AssignmentModeHandler.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation

/// Service that implements mode-specific logic for the three assignment modes.
///
/// - **Differentiation**: Teacher assigns different exercises to different students/groups.
///   Shows which step is wrong (firstErrorIndex). Allows 2nd chance.
///
/// - **Levels**: Students auto-progress through difficulty levels.
///   3 correct first-attempt submissions in a row → advance to next difficulty level.
///   2nd-try success resets the consecutive counter to 0.
///
/// - **Evaluation**: No feedback shown to students. Single attempt.
///   Teacher sees all results in statistics.
final class AssignmentModeHandler {

    static let shared = AssignmentModeHandler()

    private init() {}

    // MARK: - Determine Final Result

    /// Determine the `SubmissionResult` based on correction outcome, attempt number, and mode.
    ///
    /// - Parameters:
    ///   - correctionResult: The step-by-step correction from the pipeline.
    ///   - attemptNumber: 1 or 2.
    ///   - mode: The assignment mode.
    /// - Returns: The `SubmissionResult` for this submission.
    func determineFinalResult(
        correctionResult: CorrectionResult,
        attemptNumber: Int,
        mode: AssignmentMode
    ) -> SubmissionResult {
        let allCorrect = correctionResult.stepResults.allSatisfy { $0 }

        switch mode {
        case .differentiation, .levels:
            if allCorrect {
                return attemptNumber == 1 ? .success1st : .success2nd
            } else {
                // If first attempt: stays as .failed but mode may allow retry
                // If second attempt (or mode doesn't allow): definitive .failed
                return .failed
            }

        case .evaluation:
            // Evaluation mode: single attempt, no second chance
            return allCorrect ? .success1st : .failed
        }
    }

    // MARK: - 2nd Chance Eligibility

    /// Whether the student can retry this exercise given the current state.
    ///
    /// - Parameters:
    ///   - mode: The assignment mode.
    ///   - submissions: All submissions for this exercise by this student.
    /// - Returns: True if a 2nd attempt is allowed.
    func canRetry(
        mode: AssignmentMode,
        submissions: [Submission]
    ) -> Bool {
        guard mode.allows2ndChance else { return false }

        let firstAttempt = submissions.first { $0.attemptNumber == 1 }
        let secondAttempt = submissions.first { $0.attemptNumber == 2 }

        // Can retry if:
        // 1. There's a first attempt
        // 2. First attempt wasn't a success
        // 3. No second attempt yet
        guard let first = firstAttempt else { return false }
        guard first.finalResult != .success1st else { return false }
        return secondAttempt == nil
    }

    // MARK: - Levels Mode: Progression Logic

    /// Tracks consecutive first-attempt successes for level progression.
    struct LevelProgress {
        /// Number of consecutive first-attempt correct answers.
        var consecutiveCorrect: Int = 0
        /// Current difficulty level (1-5).
        var currentLevel: Int = 1
        /// Whether the student just advanced a level.
        var didAdvance: Bool = false
    }

    /// Compute level progression after a new submission.
    ///
    /// Rules:
    /// - 3 correct first-attempt submissions in a row → advance difficulty level.
    /// - A second-try success resets the consecutive counter to 0 (no progress).
    /// - A failure resets the counter to 0.
    /// - Maximum level is 5.
    ///
    /// - Parameters:
    ///   - existingSubmissions: All past submissions for this student in the assignment,
    ///     sorted by timestamp ascending.
    ///   - newResult: The result of the latest submission.
    ///   - attemptNumber: Attempt number of the latest submission.
    /// - Returns: Updated `LevelProgress`.
    func computeLevelProgress(
        existingSubmissions: [Submission],
        newResult: SubmissionResult,
        attemptNumber: Int
    ) -> LevelProgress {
        // Count consecutive first-attempt successes from the existing submissions
        var consecutive = countConsecutiveFirstAttemptSuccesses(from: existingSubmissions)

        // Apply the new result
        switch newResult {
        case .success1st:
            consecutive += 1
        case .success2nd:
            // 2nd chance success resets consecutive counter
            consecutive = 0
        case .failed:
            consecutive = 0
        }

        // Determine current level based on the exercises completed
        // For simplicity, we track advancement threshold: every 3 consecutive = +1 level
        let currentLevel = computeCurrentLevel(from: existingSubmissions)
        var didAdvance = false

        if consecutive >= 3 {
            // Advance to next level
            let newLevel = min(currentLevel + 1, 5)
            didAdvance = newLevel > currentLevel
            // Reset counter after advancement
            consecutive = 0
        }

        return LevelProgress(
            consecutiveCorrect: consecutive,
            currentLevel: didAdvance ? min(currentLevel + 1, 5) : currentLevel,
            didAdvance: didAdvance
        )
    }

    /// Count the trailing consecutive first-attempt successes in a sorted submission list.
    private func countConsecutiveFirstAttemptSuccesses(from submissions: [Submission]) -> Int {
        // Look at the most recent submissions (attempt 1 only) in reverse
        let firstAttempts = submissions
            .filter { $0.attemptNumber == 1 && $0.finalResult != nil }
            .sorted { $0.timestamp < $1.timestamp }

        var count = 0
        for submission in firstAttempts.reversed() {
            if submission.finalResult == .success1st {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    /// Compute the current difficulty level based on submission history.
    private func computeCurrentLevel(from submissions: [Submission]) -> Int {
        // Count total level-ups: every 3 consecutive first-attempt successes = +1
        let firstAttempts = submissions
            .filter { $0.attemptNumber == 1 && $0.finalResult != nil }
            .sorted { $0.timestamp < $1.timestamp }

        var level = 1
        var consecutive = 0

        for submission in firstAttempts {
            if submission.finalResult == .success1st {
                consecutive += 1
                if consecutive >= 3 {
                    level = min(level + 1, 5)
                    consecutive = 0
                }
            } else {
                consecutive = 0
            }
        }

        return level
    }

    // MARK: - Feedback Configuration

    /// What feedback information to show based on the mode.
    struct FeedbackConfig {
        /// Whether to show any feedback at all.
        var showsFeedback: Bool
        /// Whether to show per-step correctness.
        var showsStepDetails: Bool
        /// Whether to highlight the first error step.
        var showsFirstError: Bool
        /// Whether to offer a retry button.
        var offersRetry: Bool
        /// Feedback message to display.
        var message: String
    }

    /// Generate the feedback configuration for a given result and mode.
    func feedbackConfig(
        result: SubmissionResult?,
        mode: AssignmentMode,
        canRetry: Bool
    ) -> FeedbackConfig {
        switch mode {
        case .differentiation:
            return FeedbackConfig(
                showsFeedback: true,
                showsStepDetails: true,
                showsFirstError: true,
                offersRetry: canRetry,
                message: feedbackMessage(result: result, mode: mode)
            )

        case .levels:
            return FeedbackConfig(
                showsFeedback: true,
                showsStepDetails: false,
                showsFirstError: false,
                offersRetry: canRetry,
                message: feedbackMessage(result: result, mode: mode)
            )

        case .evaluation:
            return FeedbackConfig(
                showsFeedback: false,
                showsStepDetails: false,
                showsFirstError: false,
                offersRetry: false,
                message: "Votre travail a été enregistré."
            )
        }
    }

    private func feedbackMessage(result: SubmissionResult?, mode: AssignmentMode) -> String {
        guard let result = result else {
            return "Correction en cours…"
        }

        switch result {
        case .success1st:
            return "Excellent ! Réponse correcte du premier coup."
        case .success2nd:
            return "Bien joué ! Réponse correcte au deuxième essai."
        case .failed:
            if mode == .differentiation {
                return "La réponse n'est pas correcte. Consultez le détail des étapes."
            } else {
                return "La réponse n'est pas correcte. Revisez cette notion."
            }
        }
    }
}
