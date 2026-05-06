//
//  AddExerciseView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.11.2024.
//

import SwiftUI
import PhotosUI

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

    // Image import (ISSUE-012 — iPad teachers need parity with macOS).
    @State private var pickedImage: PhotosPickerItem?
    @State private var importedImageURL: String?
    @State private var isExtracting: Bool = false
    @State private var importedPreviewImage: UIImage?
    @State private var creationMethod: ExerciseCreationMethod = .wysiwyg

    var body: some View {
        NavigationView {
            Form {
                // Image import (optional)
                imageImportSection

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

    // MARK: - Image Import (ISSUE-012)

    @ViewBuilder
    private var imageImportSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Photographiez ou choisissez une image de l'énoncé pour pré-remplir automatiquement le titre, l'énoncé et la réponse attendue.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    PhotosPicker(
                        selection: $pickedImage,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Choisir une photo", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isExtracting)

                    if isExtracting {
                        ProgressView()
                            .scaleEffect(0.85)
                        Text("Extraction…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let preview = importedPreviewImage {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 160)
                        .cornerRadius(6)
                }
            }
        } header: {
            Text("Importer depuis une photo")
        }
        .onChange(of: pickedImage) { _, newItem in
            guard let newItem else { return }
            Task { await handleImagePicked(newItem) }
        }
    }

    private func handleImagePicked(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            errorMessage = "Impossible de lire l'image sélectionnée."
            showError = true
            return
        }

        importedPreviewImage = image
        isExtracting = true
        defer { isExtracting = false }

        do {
            // Re-encode as JPEG @0.85 to keep upload size reasonable. The
            // Cloud Function detects MIME from the file extension, so we
            // must upload to a `.jpg` path.
            let payload = image.jpegData(compressionQuality: 0.85) ?? data
            let path = "exercises/\(UUID().uuidString).jpg"
            let stored = try await DataService.shared.uploadData(payload, path: path)
            importedImageURL = stored

            let extraction = try await ExerciseExtractionService.shared
                .extractExercise(storagePath: stored)

            if statement.isEmpty { statement = extraction.statement }
            if expectedAnswer.isEmpty { expectedAnswer = extraction.expectedAnswer }
            if title.isEmpty {
                // Use the first non-empty line of the statement as a tentative
                // title. The teacher can rename before saving.
                let firstLine = extraction.statement
                    .split(whereSeparator: \.isNewline)
                    .first
                    .map(String.init) ?? ""
                title = String(firstLine.prefix(60))
            }
            creationMethod = .image
            showPreview = true
        } catch {
            errorMessage = "Échec de l'extraction : \(error.localizedDescription)"
            showError = true
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
            statementImageURL: importedImageURL,
            expectedAnswer: expectedAnswer,
            chapterID: selectedChapterID,
            difficultyLevel: difficultyLevel,
            creationMethod: creationMethod,
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
