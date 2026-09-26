//
//  ExerciseWindowManager.swift
//  MathClass
//
//  Created by Xavier Morvan on 28.03.2025.
//

import SwiftUI
import AppKit

/// Manages exercise editor windows (macOS).
/// Updated for Phase 3: points to unified ExerciseEditorView_macOS.
class ExerciseWindowManager: ObservableObject {
    private var windowControllers: [String: ExerciseWindowController] = [:]

    @Published var isAddSheetPresented = false
    @Published var isEditSheetPresented = false
    @Published var exerciseToEdit: Exercise? = nil
    @Published var isAnyWindowOpen: Bool = false

    // MARK: - Native macOS Windows

    @MainActor
    func openAddExerciseWindow(with viewModel: TeacherViewModel) {
        closeWindow(id: "add")

        let content = ExerciseEditorView_macOS(teacherViewModel: viewModel)
            .environmentObject(self)

        let controller = ExerciseWindowController.create(
            title: "Nouvel exercice",
            content: content,
            onClose: { [weak self] in
                self?.windowDidClose(id: "add")
            }
        )

        windowControllers["add"] = controller
        controller.show()
        isAnyWindowOpen = true
    }

    @MainActor
    func openEditExerciseWindow(exercise: Exercise, viewModel: TeacherViewModel) {
        closeWindow(id: "edit")

        let content = ExerciseEditorView_macOS(teacherViewModel: viewModel, exercise: exercise)
            .environmentObject(self)

        let controller = ExerciseWindowController.create(
            title: "Modifier: \(exercise.displayTitle)",
            content: content,
            onClose: { [weak self] in
                self?.windowDidClose(id: "edit")
            }
        )

        windowControllers["edit"] = controller
        controller.show()
        isAnyWindowOpen = true
    }

    @MainActor
    func closeWindow(id: String) {
        if let controller = windowControllers[id] {
            controller.close()
            windowControllers.removeValue(forKey: id)
            updateWindowStatus()
        }
    }

    @MainActor
    func closeAddExerciseWindow() {
        closeWindow(id: "add")
    }

    @MainActor
    func closeEditExerciseWindow() {
        closeWindow(id: "edit")
    }

    @MainActor
    func closeAllWindows() {
        for (id, _) in windowControllers {
            closeWindow(id: id)
        }
    }

    // MARK: - Sheet Alternatives

    func presentAddSheet() {
        isAddSheetPresented = true
    }

    func presentEditSheet(exercise: Exercise) {
        exerciseToEdit = exercise
        isEditSheetPresented = true
    }

    func dismissAddSheet() {
        isAddSheetPresented = false
    }

    func dismissEditSheet() {
        isEditSheetPresented = false
        exerciseToEdit = nil
    }

    // MARK: - Helpers

    private func windowDidClose(id: String) {
        windowControllers.removeValue(forKey: id)
        updateWindowStatus()
    }

    private func updateWindowStatus() {
        isAnyWindowOpen = !windowControllers.isEmpty
    }
}
