//
//  ImageImportPanel_macOS.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import SwiftUI
import AppKit

/// Image import panel: drop/select an image → "Extract with AI" → review/edit extracted LaTeX.
struct ImageImportPanel_macOS: View {
    @ObservedObject var viewModel: ExerciseEditorViewModel

    var body: some View {
        HSplitView {
            imageSection
                .frame(minWidth: 300)
            extractedSection
                .frame(minWidth: 300)
        }
    }

    // MARK: - Image Section

    private var imageSection: some View {
        VStack(spacing: 16) {
            sectionLabel("Image de l'exercice".tr)

            if let imageData = viewModel.importedImageData,
               let nsImage = NSImage(data: imageData) {
                // Show imported image
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 400)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )

                HStack {
                    Button("Changer l'image".tr) {
                        viewModel.selectImage()
                    }

                    Spacer()

                    Button {
                        Task { await viewModel.extractFromImage() }
                    } label: {
                        Label("Extraire avec l'IA".tr, systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isExtracting)
                }
            } else {
                // Drop zone / select button
                dropZone
            }

            if viewModel.isExtracting {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Extraction en cours…".tr)
                        .foregroundColor(.secondary)
                }
            }

            if let error = viewModel.extractionError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Glissez une image ici".tr)
                .font(.headline)
                .foregroundColor(.secondary)

            Text("ou".tr)
                .foregroundColor(.secondary)

            Button("Sélectionner un fichier".tr) {
                viewModel.selectImage()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundColor(.gray.opacity(0.3))
        )
        .onDrop(of: [.image], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - Extracted Content Section

    private var extractedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Énoncé extrait (modifiable)".tr)

            TextEditor(text: $viewModel.statement)
                .font(.system(.body, design: .monospaced))
                .padding(8)

            Divider()

            sectionLabel("Aperçu".tr)

            if viewModel.statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("L'énoncé extrait apparaîtra ici après l'extraction…".tr)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding()
            } else {
                KaTeXView(
                    content: viewModel.statement,
                    mode: .preview,
                    fontSize: 18,
                    minHeight: 80
                )
            }

            Divider()

            sectionLabel("Réponse attendue".tr)

            TextField("Réponse attendue".tr, text: $viewModel.expectedAnswer)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .padding(8)

            if !viewModel.expectedAnswer.isEmpty {
                KaTeXView(
                    content: "$\(viewModel.expectedAnswer)$",
                    mode: .preview,
                    fontSize: 16,
                    minHeight: 40
                )
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, error in
            if let data = data {
                DispatchQueue.main.async {
                    viewModel.importedImageData = data
                    viewModel.creationMethod = .image
                    viewModel.isDirty = true
                }
            }
        }
        return true
    }
}
