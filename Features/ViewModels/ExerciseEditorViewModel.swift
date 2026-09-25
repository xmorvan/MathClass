//
//  ExerciseEditorViewModel.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import Combine
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// Shared ViewModel for exercise creation and editing.
/// Replaces ExerciseBlockViewModel and ExerciseEditorModel_macOS.
///
/// Two creation methods:
/// - WYSIWYG: Teacher writes LaTeX/text in a textarea with live KaTeX preview.
/// - Image Import: Teacher drops/selects an image → Cloud Function extracts LaTeX → review.
@MainActor
class ExerciseEditorViewModel: ObservableObject {

    // MARK: - Exercise Properties

    @Published var title: String = ""
    @Published var statement: String = ""
    @Published var expectedAnswer: String = ""
    @Published var difficultyLevel: Int = 1
    @Published var selectedChapterID: String?
    @Published var selectedCompetencyIDs: Set<String> = []
    @Published var creationMethod: ExerciseCreationMethod = .wysiwyg

    // MARK: - Image Import State

    @Published var importedImageData: Data?
    @Published var importedImageURL: String?
    @Published var isExtracting: Bool = false
    @Published var extractionError: String?

    // MARK: - UI State

    @Published var isDirty: Bool = false
    @Published var isSaving: Bool = false
    @Published var saveError: String?
    @Published var showSaveError: Bool = false

    // MARK: - Internal

    /// The original exercise being edited (nil for new exercise).
    let originalExercise: Exercise?

    /// The teacher ViewModel used for CRUD operations.
    /// Exposed so the editor can pick the class whose chapters are listed.
    let teacherViewModel: TeacherViewModel

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(teacherViewModel: TeacherViewModel, exercise: Exercise? = nil) {
        self.teacherViewModel = teacherViewModel
        self.originalExercise = exercise

        if let exercise = exercise {
            self.title = exercise.title
            self.statement = exercise.statement
            self.expectedAnswer = exercise.expectedAnswer
            self.difficultyLevel = exercise.difficultyLevel
            self.selectedChapterID = exercise.chapterID
            self.selectedCompetencyIDs = Set(exercise.competencyIDs)
            self.creationMethod = exercise.creationMethod
            self.importedImageURL = exercise.statementImageURL
        }

        setupDirtyTracking()
    }

    private func setupDirtyTracking() {
        // Track changes on any published property. Combine sinks fire on
        // the publisher's thread by default — `.receive(on: .main)` keeps
        // the @Published `isDirty` mutation on the MainActor.
        Publishers.CombineLatest4($title, $statement, $expectedAnswer, $difficultyLevel)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.isDirty = true }
            .store(in: &cancellables)

        Publishers.CombineLatest($selectedChapterID, $selectedCompetencyIDs)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.isDirty = true }
            .store(in: &cancellables)

        $creationMethod
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.isDirty = true }
            .store(in: &cancellables)
    }

    // MARK: - Available Chapters & Competencies

    var availableChapters: [Chapter] {
        teacherViewModel.chapters
    }

    func competencies(for chapterID: String) -> [Competency] {
        teacherViewModel.chapterRepo.competencies[chapterID] ?? []
    }

    // MARK: - Image Import

    /// Select an image file from disk (macOS only).
    #if os(macOS)
    func selectImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                importedImageData = data
                creationMethod = .image
                isDirty = true
            } catch {
                extractionError = LocalizationManager.shared.format("Impossible de charger l'image : %@", error.localizedDescription)
            }
        }
    }
    #endif

    /// Extract LaTeX from the imported image using the Cloud Function.
    func extractFromImage() async {
        guard let imageData = importedImageData else {
            extractionError = "Aucune image sélectionnée.".tr
            return
        }

        isExtracting = true
        extractionError = nil

        do {
            // Upload image to Cloud Storage
            let storagePath = try await teacherViewModel.uploadExerciseImage(imageData)
            importedImageURL = storagePath

            // Call extraction service
            let result = try await ExerciseExtractionService.shared.extractExercise(storagePath: storagePath)
            self.statement = result.statement
            self.expectedAnswer = result.expectedAnswer
            self.creationMethod = .image
            self.isDirty = true
        } catch {
            extractionError = LocalizationManager.shared.format("Erreur d'extraction : %@", error.localizedDescription)
        }

        isExtracting = false
    }

    // MARK: - Validation

    func validate() -> (isValid: Bool, error: String?) {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (false, "Le titre ne peut pas être vide.")
        }
        if statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (false, "L'énoncé ne peut pas être vide.")
        }
        return (true, nil)
    }

    // MARK: - Save

    func save(andClose: Bool = false) async -> Bool {
        let validation = validate()
        guard validation.isValid else {
            saveError = validation.error
            showSaveError = true
            return false
        }

        isSaving = true

        do {
            let exercise = buildExercise()

            if originalExercise?.id != nil {
                try await teacherViewModel.updateExercise(exercise)
            } else {
                try await teacherViewModel.addExercise(exercise)
            }

            isDirty = false
            isSaving = false
            return true
        } catch {
            saveError = LocalizationManager.shared.format("Échec de la sauvegarde : %@", error.localizedDescription)
            showSaveError = true
            isSaving = false
            return false
        }
    }

    // MARK: - Build Exercise

    private func buildExercise() -> Exercise {
        Exercise(
            id: originalExercise?.id,
            title: title,
            statement: statement,
            statementImageURL: importedImageURL ?? originalExercise?.statementImageURL,
            expectedAnswer: expectedAnswer,
            chapterID: selectedChapterID,
            competencyIDs: Array(selectedCompetencyIDs),
            difficultyLevel: difficultyLevel,
            creationMethod: creationMethod,
            teacherID: originalExercise?.teacherID
                ?? (AuthenticationService.shared.currentUser?.uid ?? ""),
            createdAt: originalExercise?.createdAt ?? Date()
        )
    }
}
