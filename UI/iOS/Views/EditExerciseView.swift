//
//  EditExerciseView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.11.2024.
//

import SwiftUI

/// Sheet for editing an exercise on iPad.
/// Shows the exercise with KaTeX preview, difficulty, and chapter selection.
struct EditExerciseView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: TeacherViewModel
    let exercise: Exercise

    @State private var title: String
    @State private var statement: String
    @State private var expectedAnswer: String
    @State private var difficultyLevel: Int
    @State private var selectedChapterID: String?
    @State private var showPreview: Bool = true

    init(viewModel: TeacherViewModel, exercise: Exercise) {
        self.viewModel = viewModel
        self.exercise = exercise
        _title = State(initialValue: exercise.title)
        _statement = State(initialValue: exercise.statement)
        _expectedAnswer = State(initialValue: exercise.expectedAnswer)
        _difficultyLevel = State(initialValue: exercise.difficultyLevel)
        _selectedChapterID = State(initialValue: exercise.chapterID)
    }

    var body: some View {
        NavigationView {
            Form {
                // Title
                Section(header: Text("Titre".tr)) {
                    TextField("Titre".tr, text: $title)
                }

                // Statement
                Section(header: Text("Énoncé (LaTeX et texte)".tr)) {
                    TextEditor(text: $statement)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 180)

                    if showPreview && !statement.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Aperçu".tr)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            KaTeXView(content: statement, mode: .preview, fontSize: 16, minHeight: 60)
                                .frame(minHeight: 60)
                                .background(Color.gray.opacity(0.05))
                                .cornerRadius(8)
                        }
                    }

                    Toggle("Afficher l'aperçu".tr, isOn: $showPreview)
                }

                // Expected Answer
                Section(header: Text("Réponse attendue (LaTeX)".tr)) {
                    TextField("ex: x = 5".tr, text: $expectedAnswer)
                        .font(.system(.body, design: .monospaced))

                    if showPreview && !expectedAnswer.isEmpty {
                        KaTeXView(
                            content: "$\(expectedAnswer)$",
                            mode: .preview,
                            fontSize: 16,
                            minHeight: 40
                        )
                    }
                }

                // Difficulty
                Section(header: Text("Difficulté".tr)) {
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { level in
                            Button {
                                difficultyLevel = level
                            } label: {
                                Image(systemName: level <= difficultyLevel ? "star.fill" : "star")
                                    .foregroundColor(level <= difficultyLevel ? .yellow : .gray)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        Text(LocalizationManager.shared.format("Niveau %@", String(difficultyLevel)))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Chapter
                if !viewModel.chapters.isEmpty {
                    Section(header: Text("Chapitre".tr)) {
                        Picker("Chapitre".tr, selection: $selectedChapterID) {
                            Text("Aucun".tr).tag(String?.none)
                            ForEach(viewModel.chapters) { chapter in
                                Text(chapter.name).tag(Optional(chapter.id))
                            }
                        }
                    }
                }

                // Source image (if image-based)
                if let imageURL = exercise.statementImageURL {
                    Section(header: Text("Image source".tr)) {
                        AsyncImageFromStorage(path: imageURL)
                    }
                }
            }
            .navigationTitle("Modifier l'exercice".tr)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler".tr) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sauvegarder".tr) {
                        saveExercise()
                    }
                    .disabled(title.isEmpty || statement.isEmpty)
                }
            }
        }
    }

    private func saveExercise() {
        var updated = exercise
        updated.title = title
        updated.statement = statement
        updated.expectedAnswer = expectedAnswer
        updated.difficultyLevel = difficultyLevel
        updated.chapterID = selectedChapterID
        Task {
            try? await viewModel.updateExercise(updated)
            dismiss()
        }
    }
}
