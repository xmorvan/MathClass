//
//  StudentViewModel.swift
//  MathClass
//
//  Created by Xavier Morvan on 18.11.2024.
//

import Foundation
// Per CLAUDE.md, ViewModels must not import SwiftUI. The legacy
// `submitSolution` method (which talked to FirebaseStorage directly) is
// gone — the live submission flow now goes through SubmissionViewModel +
// DataService.uploadData, so neither SwiftUI, FirebaseStorage nor
// FirebaseFirestore are needed in this ViewModel.

/// ViewModel for the student exercise experience.
/// Manages assignment loading, exercise navigation, submission, and mode logic.
@MainActor
class StudentViewModel: ObservableObject {

    // MARK: - Published State

    @Published var activeAssignments: [Assignment] = []
    @Published var selectedAssignment: Assignment?
    @Published var assignedExercises: [Exercise] = []
    @Published var currentExerciseIndex: Int = 0
    @Published var currentExercise: Exercise?
    @Published var isLoading: Bool = false
    @Published var error: String?

    /// Progress: number of exercises completed in the current assignment.
    @Published var completedCount: Int = 0

    /// Whether the active assignment lets the student pick any exercise
    /// rather than walking them in order. Mirrors `Assignment.isFreeOrder`
    /// (legacy path) and `Session.allowFreeOrder` (new path). The view
    /// renders a card grid when `true`; otherwise it forces `currentExercise`
    /// via `advanceToNextExercise`.
    @Published private(set) var allowFreeOrder: Bool = false

    /// Exercises still available for the student to pick when in free-order
    /// mode (i.e. `assignedExercises` minus those already completed).
    @Published private(set) var freeOrderDeck: [Exercise] = []

    // MARK: - Configuration

    let studentID: String
    let classID: String

    private let assignmentRepo: AssignmentRepository
    private let exerciseRepo: ExerciseRepository
    private let submissionRepo: SubmissionRepository
    private let classRepo: ClassRepository

    /// Class-level notation strictness setting. Read once on demand via the
    /// class repo. Defaults to true (strict) for legacy classes that don't
    /// carry the field yet.
    @Published private(set) var notationStrict: Bool = true

    // MARK: - Init

    init(
        studentID: String,
        classID: String,
        assignmentRepo: AssignmentRepository? = nil,
        exerciseRepo: ExerciseRepository? = nil,
        submissionRepo: SubmissionRepository? = nil,
        classRepo: ClassRepository? = nil
    ) {
        self.studentID = studentID
        self.classID = classID
        let dataService = DataService.shared
        self.assignmentRepo = assignmentRepo ?? dataService.assignmentRepository
        self.exerciseRepo = exerciseRepo ?? dataService.exerciseRepository
        self.submissionRepo = submissionRepo ?? dataService.submissionRepository
        self.classRepo = classRepo ?? dataService.classRepository

        // Best-effort fetch of the class doc to know notation strictness.
        // The student session has no auth so the class is publicly
        // readable per firestore.rules.
        Task { [weak self] in
            guard let self else { return }
            do {
                let cls = try await self.classRepo.getClass(id: classID)
                await MainActor.run { self.notationStrict = cls.isNotationStrict }
            } catch {
                // Default stays true (strict).
            }
        }
    }

    // MARK: - Listeners

    /// Start listening for active assignments in the student's class.
    func startListening() {
        assignmentRepo.startListening(classID: classID)
    }

    func stopListening() {
        assignmentRepo.stopListening()
        submissionRepo.stopListening()
    }

    // MARK: - Load Assigned Exercises

    /// Load active assignments for the student's class, then auto-select the first one.
    func loadAssignedExercises() async {
        isLoading = true
        error = nil

        // Wait briefly for the listener to populate
        try? await Task.sleep(nanoseconds: 500_000_000)

        let active = assignmentRepo.activeAssignments
        self.activeAssignments = active

        // If an assignment is already selected, reload its exercises
        if let selected = selectedAssignment {
            await loadExercises(for: selected)
        } else if let first = active.first {
            // Auto-select the first active assignment
            await loadExercises(for: first)
        } else {
            // No active assignments
            self.assignedExercises = []
            self.currentExercise = nil
        }

        isLoading = false
    }

    /// Load exercises for a specific assignment.
    func loadExercises(for assignment: Assignment) async {
        guard let assignmentID = assignment.id else { return }
        isLoading = true
        selectedAssignment = assignment
        allowFreeOrder = assignment.isFreeOrder

        do {
            // Get exercises assigned to this student
            let assignmentExercises = try await assignmentRepo.getExercisesForStudent(
                assignmentID: assignmentID,
                studentID: studentID
            )

            // Load the actual exercise objects
            let exerciseIDs = assignmentExercises.map { $0.exerciseID }
            let exercises = try await exerciseRepo.getExercises(ids: exerciseIDs)

            // Sort exercises by assignment order
            let orderedIDs = assignmentExercises.sorted { $0.order < $1.order }.map { $0.exerciseID }
            self.assignedExercises = orderedIDs.compactMap { id in
                exercises.first { $0.id == id }
            }

            // Start listening for this student's submissions in this assignment
            submissionRepo.startListening(studentID: studentID, assignmentID: assignmentID)

            // Compute progress and set current exercise. In free-order mode
            // the deck is the source of truth and `currentExercise` stays
            // nil until the student explicitly picks one.
            updateProgress()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    /// In free-order mode, lock in the picked exercise as the current one.
    /// Has no effect in linear mode.
    func selectFromDeck(_ exercise: Exercise) {
        guard allowFreeOrder, let id = exercise.id else { return }
        guard let index = assignedExercises.firstIndex(where: { $0.id == id }) else { return }
        currentExerciseIndex = index
        currentExercise = exercise
    }

    /// In free-order mode, return to the deck after submitting one exercise.
    /// Has no effect in linear mode.
    func returnToDeck() {
        guard allowFreeOrder else { return }
        currentExercise = nil
        rebuildFreeOrderDeck()
    }

    // MARK: - Exercise Navigation

    /// Move to the next exercise in the assignment.
    func advanceToNextExercise() {
        currentExerciseIndex += 1
        if currentExerciseIndex < assignedExercises.count {
            currentExercise = assignedExercises[currentExerciseIndex]
        } else {
            currentExercise = nil
        }
        updateProgress()
    }

    /// Select a specific exercise by index.
    func selectExercise(at index: Int) {
        guard index >= 0 && index < assignedExercises.count else { return }
        currentExerciseIndex = index
        currentExercise = assignedExercises[index]
    }

    // MARK: - Submission Creation (used by SubmissionViewModel)

    /// Create a submission with recognized LaTeX steps.
    func createSubmission(
        latexSteps: [String],
        inkDataRef: String?,
        pngURL: String?,
        timeSpent: TimeInterval,
        attemptNumber: Int = 1
    ) async throws -> String {
        guard let exerciseID = currentExercise?.id,
              let assignmentID = selectedAssignment?.id else {
            throw StudentError.noCurrentExercise
        }

        let submission = Submission(
            studentID: studentID,
            exerciseID: exerciseID,
            assignmentID: assignmentID,
            attemptNumber: attemptNumber,
            inkDataRef: inkDataRef,
            pngURL: pngURL,
            latexSteps: latexSteps,
            timeSpent: timeSpent
        )

        return try await submissionRepo.createSubmission(submission)
    }

    /// Update a submission with correction results.
    func updateSubmissionWithResult(
        _ submission: Submission,
        correctionResult: CorrectionResult,
        finalResult: SubmissionResult
    ) async throws {
        var updated = submission
        updated.correctionResult = correctionResult
        updated.finalResult = finalResult
        try await submissionRepo.updateSubmission(updated)
    }

    // MARK: - Assignment Mode Queries

    /// Get the current assignment mode.
    var currentMode: AssignmentMode? {
        selectedAssignment?.mode
    }

    /// Get existing submissions for a specific exercise.
    func existingSubmissions(for exerciseID: String) -> [Submission] {
        submissionRepo.submissions.filter { $0.exerciseID == exerciseID }
    }

    /// Check if the student can attempt a 2nd try for the current exercise.
    func canRetry(exerciseID: String) -> Bool {
        guard let mode = currentMode, mode.allows2ndChance else { return false }
        let attempts = existingSubmissions(for: exerciseID)
        let hasFirstAttempt = attempts.contains { $0.attemptNumber == 1 }
        let hasSecondAttempt = attempts.contains { $0.attemptNumber == 2 }
        let firstFailed = attempts.first(where: { $0.attemptNumber == 1 })?.finalResult != .success1st
        return hasFirstAttempt && !hasSecondAttempt && firstFailed
    }

    /// Check if an exercise has already been completed.
    /// An exercise is considered completed if it has a successful result,
    /// has failed on all allowed attempts, or has any submission (when no correction pipeline is active).
    func isExerciseCompleted(_ exerciseID: String) -> Bool {
        let attempts = existingSubmissions(for: exerciseID)
        guard !attempts.isEmpty else { return false }
        // If any attempt has a definitive result, use that
        if attempts.contains(where: { $0.finalResult?.isSuccess == true }) { return true }
        if attempts.contains(where: { $0.finalResult == .failed && $0.attemptNumber >= 2 }) { return true }
        // If no correction result at all, treat having a submission as completed
        // (the correction pipeline will update the result later)
        if attempts.allSatisfy({ $0.finalResult == nil }) { return true }
        return false
    }

    // MARK: - Progress

    private func updateProgress() {
        completedCount = assignedExercises.filter { exercise in
            guard let id = exercise.id else { return false }
            return isExerciseCompleted(id)
        }.count

        if allowFreeOrder {
            // In free-order mode the deck drives the UI and `currentExercise`
            // only fills when the student picks one. Don't auto-advance.
            rebuildFreeOrderDeck()
            return
        }

        // Linear mode: snap to the first uncompleted exercise.
        if let firstUncompletedIndex = assignedExercises.firstIndex(where: { exercise in
            guard let id = exercise.id else { return true }
            return !isExerciseCompleted(id)
        }) {
            currentExerciseIndex = firstUncompletedIndex
            currentExercise = assignedExercises[firstUncompletedIndex]
        } else {
            // All done
            currentExercise = nil
        }
    }

    private func rebuildFreeOrderDeck() {
        freeOrderDeck = assignedExercises.filter { exercise in
            guard let id = exercise.id else { return true }
            return !isExerciseCompleted(id)
        }
    }

    // MARK: - Errors

    enum StudentError: LocalizedError {
        case noCurrentExercise

        var errorDescription: String? {
            switch self {
            case .noCurrentExercise: return "Aucun exercice en cours."
            }
        }
    }
}
