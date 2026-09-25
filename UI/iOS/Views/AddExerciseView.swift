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
    @State private var suggestedCompetencyIDs: [String] = []
    @State private var acceptedCompetencyIDs: Set<String> = []

    var body: some View {
        NavigationView {
            Form {
                // Image import (optional)
                imageImportSection

                // Title
                Section(header: Text("Titre de l'exercice".tr)) {
                    TextField("Entrez le titre".tr, text: $title)
                }

                // Statement
                Section(header: Text("Énoncé (LaTeX et texte)".tr)) {
                    TextEditor(text: $statement)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 150)

                    InlineHint("Utilisez $...$ pour les formules en ligne et $$...$$ pour les formules centrées.", icon: "info.circle")

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

                    InlineHint("La correction comparera l'étape finale de l'élève à cette réponse (en équivalence algébrique).", icon: "checkmark.seal")

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

                // Suggested competencies (AI)
                if !suggestedCompetencyIDs.isEmpty {
                    Section {
                        Text("L'IA propose ces compétences. Décochez celles qui ne correspondent pas.".tr)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(suggestedCompetencyIDs, id: \.self) { competencyID in
                            HStack {
                                Image(systemName: acceptedCompetencyIDs.contains(competencyID) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(acceptedCompetencyIDs.contains(competencyID) ? .blue : .secondary)
                                Text(competencyLabel(for: competencyID))
                                    .font(.subheadline)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if acceptedCompetencyIDs.contains(competencyID) {
                                    acceptedCompetencyIDs.remove(competencyID)
                                } else {
                                    acceptedCompetencyIDs.insert(competencyID)
                                }
                            }
                        }
                    } header: {
                        Text("Compétences suggérées".tr)
                    }
                }
            }
            .navigationTitle("Ajouter Exercice".tr)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter".tr) {
                        addExercise()
                    }
                    .disabled(title.isEmpty || statement.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler".tr) { dismiss() }
                }
            }
            .alert("Erreur".tr, isPresented: $showError) {
                Button("OK".tr, role: .cancel) {}
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
                Text("Photographiez ou choisissez une image de l'énoncé pour pré-remplir automatiquement le titre, l'énoncé et la réponse attendue.".tr)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    PhotosPicker(
                        selection: $pickedImage,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Choisir une photo".tr, systemImage: "photo")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isExtracting)

                    if isExtracting {
                        ProgressView()
                            .scaleEffect(0.85)
                        Text("Extraction…".tr)
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
            Text("Importer depuis une photo".tr)
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

            // Build catalog from the teacher's chapters → competencies tree.
            let catalog = catalogEntriesForExtraction()

            let extraction = try await ExerciseExtractionService.shared
                .extractExercise(storagePath: stored, competencies: catalog)

            if statement.isEmpty { statement = extraction.statement }
            if expectedAnswer.isEmpty { expectedAnswer = extraction.expectedAnswer }
            if title.isEmpty {
                // Use the first non-empty line of the statement as a tentative
                // title. The teacher can rename before saving.
                let firstLine = extraction.statement
                    .split(whereSeparator: \.isNewline)
                    .first
                    .map(String.init) ?? ""
                title = String(firstLine.latexPlainPreview.prefix(60))
            }
            suggestedCompetencyIDs = extraction.suggestedCompetencyIDs
            acceptedCompetencyIDs = Set(extraction.suggestedCompetencyIDs)
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
            competencyIDs: Array(acceptedCompetencyIDs),
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

    /// Flatten the teacher's chapter→competency tree into the catalog
    /// shape expected by `ExerciseExtractionService`.
    private func catalogEntriesForExtraction() -> [ExerciseExtractionService.CatalogEntry] {
        var entries: [ExerciseExtractionService.CatalogEntry] = []
        for chapter in viewModel.chapters {
            let comps = viewModel.chapterRepo.competencies[chapter.id ?? ""] ?? []
            for c in comps {
                guard let id = c.id else { continue }
                entries.append(.init(id: id, label: "\(chapter.name) — \(c.label)"))
            }
        }
        return entries
    }

    /// Resolve a competency ID to its display label for UI rendering.
    private func competencyLabel(for id: String) -> String {
        for chapter in viewModel.chapters {
            let comps = viewModel.chapterRepo.competencies[chapter.id ?? ""] ?? []
            if let match = comps.first(where: { $0.id == id }) {
                return "\(chapter.name) — \(match.label)"
            }
        }
        return id
    }
}
