//
//  ExerciseEditorView_macOS.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import SwiftUI

/// Unified exercise editor for macOS.
/// Two creation modes (tabs): WYSIWYG and Image Import.
/// Replaces ImprovedExerciseEditorView_macOS, ExerciseEditorView_macOS,
/// EditExerciseView_macOS, and all block-based editors.
struct ExerciseEditorView_macOS: View {
    @ObservedObject var teacherViewModel: TeacherViewModel
    @EnvironmentObject var windowManager: ExerciseWindowManager
    @StateObject private var viewModel: ExerciseEditorViewModel

    @State private var showCloseConfirmation = false

    init(teacherViewModel: TeacherViewModel, exercise: Exercise? = nil) {
        self.teacherViewModel = teacherViewModel
        self._viewModel = StateObject(
            wrappedValue: ExerciseEditorViewModel(
                teacherViewModel: teacherViewModel,
                exercise: exercise
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                editorArea
                    .frame(minWidth: 450)
                metadataPanel
                    .frame(width: 280)
            }
        }
        .overlay(savingOverlay)
        .alert("Erreur de sauvegarde".tr, isPresented: $viewModel.showSaveError) {
            Button("OK".tr, role: .cancel) {}
        } message: {
            Text(viewModel.saveError ?? "Erreur inconnue")
        }
        .alert("Modifications non sauvegardées".tr, isPresented: $showCloseConfirmation) {
            Button("Annuler".tr, role: .cancel) {}
            Button("Ne pas sauvegarder".tr, role: .destructive) { closeWindow() }
            Button("Sauvegarder".tr) {
                Task {
                    let saved = await viewModel.save(andClose: true)
                    if saved { closeWindow() }
                }
            }
        } message: {
            Text("Voulez-vous sauvegarder les modifications avant de fermer ?".tr)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            TextField("Titre de l'exercice".tr, text: $viewModel.title)
                .font(.headline)
                .textFieldStyle(.roundedBorder)

            if viewModel.isDirty {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .help("Modifications non sauvegardées")
            }

            Spacer()

            Button {
                Task {
                    let saved = await viewModel.save()
                    if saved { /* stay open */ }
                }
            } label: {
                Label("Sauvegarder".tr, systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(viewModel.isSaving)

            Button {
                if viewModel.isDirty {
                    showCloseConfirmation = true
                } else {
                    closeWindow()
                }
            } label: {
                Label("Fermer".tr, systemImage: "xmark.circle")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Editor Area (tabs)

    private var editorArea: some View {
        VStack(spacing: 0) {
            // Mode picker
            Picker("Mode de création".tr, selection: $viewModel.creationMethod) {
                Text("WYSIWYG".tr).tag(ExerciseCreationMethod.wysiwyg)
                Text("Import image".tr).tag(ExerciseCreationMethod.image)
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Content based on mode
            switch viewModel.creationMethod {
            case .wysiwyg:
                WYSIWYGPanel_macOS(viewModel: viewModel)
            case .image:
                ImageImportPanel_macOS(viewModel: viewModel)
            }
        }
    }

    // MARK: - Metadata Panel

    private var metadataPanel: some View {
        ExerciseMetadataPanel_macOS(viewModel: viewModel)
    }

    // MARK: - Saving Overlay

    @ViewBuilder
    private var savingOverlay: some View {
        if viewModel.isSaving {
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Sauvegarde en cours…".tr)
                        .font(.headline)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.windowBackgroundColor))
                )
                .shadow(radius: 10)
            }
        }
    }

    // MARK: - Helpers

    private func closeWindow() {
        if viewModel.originalExercise != nil {
            windowManager.closeEditExerciseWindow()
        } else {
            windowManager.closeAddExerciseWindow()
        }
    }
}
