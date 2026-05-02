//
//  SubmissionViewModel.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
// Per CLAUDE.md, ViewModels must not import SwiftUI. The PNG upload now
// goes through DataService.shared.uploadData(...) so FirebaseStorage isn't
// needed here either — the gateway owns Storage access.

/// Manages the verify → recognize → confirm → submit → correct cycle for a single exercise.
///
/// Flow:
/// 1. Student draws on PencilKit canvas
/// 2. Taps "Verify" → uploads PNG → RecognitionService → receives LaTeX steps
/// 3. Student reviews extracted LaTeX (VerificationView) → confirms or retries
/// 4. Taps "Submit" → CorrectionService (Claude + SymPy) → receives CorrectionResult
/// 5. FeedbackView shows result based on assignment mode
/// 6. If 2nd chance allowed and first attempt failed → "Try again"
@MainActor
class SubmissionViewModel: ObservableObject {

    enum Phase: Equatable {
        case drawing
        case recognizing
        case verifying
        case submitting
        case feedback
        case retrying // 2nd chance redraw
    }

    // MARK: - Published State

    @Published var phase: Phase = .drawing
    @Published var recognizedSteps: [String] = []
    @Published var correctionResult: CorrectionResult?
    @Published var finalResult: SubmissionResult?
    @Published var error: String?
    @Published var showError: Bool = false
    @Published var levelProgress: AssignmentModeHandler.LevelProgress?

    // MARK: - Context

    let exercise: Exercise
    let assignmentMode: AssignmentMode?
    private let studentViewModel: StudentViewModel
    private let recognitionService: ClaudeRecognitionService
    private let correctionService: CorrectionService
    private let modeHandler: AssignmentModeHandler
    private var currentAttempt: Int = 1
    private var pngURL: String?
    private var timeSpent: TimeInterval = 0

    // MARK: - Init

    init(
        exercise: Exercise,
        assignmentMode: AssignmentMode?,
        studentViewModel: StudentViewModel,
        recognitionService: ClaudeRecognitionService = .shared,
        correctionService: CorrectionService = .shared,
        modeHandler: AssignmentModeHandler = .shared
    ) {
        self.exercise = exercise
        self.assignmentMode = assignmentMode
        self.studentViewModel = studentViewModel
        self.recognitionService = recognitionService
        self.correctionService = correctionService
        self.modeHandler = modeHandler

        // Check if already on 2nd attempt
        if let exerciseID = exercise.id {
            let existing = studentViewModel.existingSubmissions(for: exerciseID)
            if existing.contains(where: { $0.attemptNumber == 1 && $0.finalResult != nil }) {
                currentAttempt = 2
            }
        }
    }

    // MARK: - Step 1: Verify (Recognize Handwriting)

    /// Send the canvas PNG to recognition and receive LaTeX steps.
    func verify(imageData: Data, duration: TimeInterval) async {
        phase = .recognizing
        timeSpent = duration

        do {
            // Upload PNG to Cloud Storage via the DataService gateway
            // (replaces direct Storage.storage() access — see CLAUDE.md).
            let studentID = studentViewModel.studentID
            let exerciseID = exercise.id ?? "unknown"
            let imagePath = "submissions/\(studentID)/\(exerciseID)_attempt\(currentAttempt).png"
            _ = try await DataService.shared.uploadData(imageData, path: imagePath)
            self.pngURL = imagePath

            // Call RecognitionService via Cloud Function
            let result = try await recognitionService.recognizeFromStorage(path: imagePath)
            self.recognizedSteps = result.latexSteps
            self.phase = .verifying
        } catch let recognitionError as RecognitionError {
            switch recognitionError {
            case .lowConfidence:
                // Low confidence — still show steps but warn
                self.error = recognitionError.errorDescription
                self.showError = true
                self.phase = .verifying
            default:
                self.error = recognitionError.errorDescription ?? "Erreur de reconnaissance."
                self.showError = true
                // On recognition failure, go to verification with empty steps
                // so the student can manually enter LaTeX or submit directly
                self.recognizedSteps = []
                self.phase = .verifying
            }
        } catch {
            self.error = "Erreur lors de l'envoi: \(error.localizedDescription)"
            self.showError = true
            // Fallback: go to verification with empty steps
            self.recognizedSteps = []
            self.phase = .verifying
        }
    }

    // MARK: - Step 2: Confirm LaTeX and Submit

    /// Student confirms the recognized LaTeX steps, or provides manual corrections.
    /// Triggers correction via the hybrid Claude + SymPy pipeline.
    func confirmAndSubmit(confirmedSteps: [String]) async {
        phase = .submitting
        recognizedSteps = confirmedSteps

        do {
            // Create submission in Firestore
            let submissionID = try await studentViewModel.createSubmission(
                latexSteps: confirmedSteps,
                inkDataRef: nil,
                pngURL: pngURL,
                timeSpent: timeSpent,
                attemptNumber: currentAttempt
            )

            // In evaluation mode, no correction — just mark as submitted
            if assignmentMode == .evaluation {
                self.finalResult = nil
                self.correctionResult = nil
                self.phase = .feedback
                return
            }

            // Call CorrectionService (Claude + SymPy hybrid pipeline)
            let (correction, result) = try await correctionService.correctAndUpdate(
                submissionID: submissionID,
                studentSteps: confirmedSteps,
                expectedAnswer: exercise.expectedAnswer,
                statement: exercise.statement,
                attemptNumber: currentAttempt
            )

            self.correctionResult = correction
            self.finalResult = result

            // Compute level progression for levels mode
            if assignmentMode == .levels, let exerciseID = exercise.id {
                let existingSubmissions = studentViewModel.existingSubmissions(for: exerciseID)
                self.levelProgress = modeHandler.computeLevelProgress(
                    existingSubmissions: existingSubmissions,
                    newResult: result,
                    attemptNumber: currentAttempt
                )
            }

            self.phase = .feedback
        } catch {
            self.error = "Erreur lors de la soumission: \(error.localizedDescription)"
            self.showError = true
            self.phase = .verifying
        }
    }

    // MARK: - Step 3: Handle Feedback Actions

    /// Student chooses to retry (2nd chance).
    func startRetry() {
        guard let mode = assignmentMode, mode.allows2ndChance, currentAttempt == 1 else { return }
        currentAttempt = 2
        recognizedSteps = []
        correctionResult = nil
        finalResult = nil
        pngURL = nil
        phase = .retrying
    }

    /// Student moves on to the next exercise.
    func moveToNext() {
        studentViewModel.advanceToNextExercise()
    }

    // MARK: - Helpers

    /// Whether the student can retry this exercise.
    var canRetry: Bool {
        guard let mode = assignmentMode, mode.allows2ndChance else { return false }
        return currentAttempt == 1 && finalResult != .success1st
    }

    /// Whether feedback should be shown (based on mode).
    var showsFeedback: Bool {
        assignmentMode?.showsFeedback ?? true
    }

    /// Whether the error step is highlighted (differentiation mode).
    var showsErrorStep: Bool {
        assignmentMode?.showsErrorStep ?? false
    }
}
