//
//  AddExerciseView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.11.2024.
//

import SwiftUI

/// Sheet for adding an exercise on iPad (teacher).
/// Two creation modes: WYSIWYG (text + LaTeX) and Image Import.
/// Shows a live KaTeX preview of the statement.
struct AddExerciseView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: TeacherViewModel

    @State private var title: String = ""
    @State private var statement: String = ""
    @State private var expectedAnswer: String = ""
    @State private var difficultyLevel: Int = 1
    @State private var selectedChapterID: String?
    @State private var showPreview: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false

    var body: some View {
        NavigationView {
            Form {
                // Title
                Section(header: Text("Titre de l'exercice")) {
                    TextField("Entrez le titre", text: $title)
                }

                // Statement
                Section(header: Text("Énoncé (LaTeX et texte)")) {
                    TextEditor(text: $statement)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 150)

                    if showPreview && !statement.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Aperçu")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            KaTeXView(content: statement, mode: .preview, fontSize: 16, minHeight: 60)
                                .frame(minHeight: 60)
                                .background(Color.gray.opacity(0.05))
                                .cornerRadius(8)
                        }
                    }

                    Toggle("Afficher l'aperçu", isOn: $showPreview)
                }

                // Expected Answer
                Section(header: Text("Réponse attendue (LaTeX)")) {
                    TextField("ex: x = 5", text: $expectedAnswer)
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
                Section(header: Text("Difficulté")) {
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
                        Text("Niveau \(difficultyLevel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Chapter
                if !viewModel.chapters.isEmpty {
                    Section(header: Text("Chapitre")) {
                        Picker("Chapitre", selection: $selectedChapterID) {
                            Text("Aucun").tag(String?.none)
                            ForEach(viewModel.chapters) { chapter in
                                Text(chapter.name).tag(Optional(chapter.id))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Ajouter Exercice")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        addExercise()
                    }
                    .disabled(title.isEmpty || statement.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .alert("Erreur", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Une erreur s'est produite.")
            }
        }
    }

    private func addExercise() {
        // Previously this method silently `return`-ed when the auth state was
        // missing, leaving the user staring at an "Ajouter" button that did
        // nothing. Surface the issue via the standard alert path instead.
        guard let teacherID = AuthenticationService.shared.currentUser?.uid else {
            errorMessage = "Vous n'êtes pas connecté. Veuillez vous reconnecter."
            showError = true
            return
        }
        let newExercise = Exercise(
            title: title,
            statement: statement,
            expectedAnswer: expectedAnswer,
            chapterID: selectedChapterID,
            difficultyLevel: difficultyLevel,
            creationMethod: .wysiwyg,
            teacherID: teacherID
        )
        Task {
            do {
                try await viewModel.addExercise(newExercise)
                dismiss()
            } catch {
                errorMessage = "Échec de l'ajout : \(error.localizedDescription)"
                showError = true
            }
        }
    }
}
