//
//  ExerciseMetadataPanel_macOS.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import SwiftUI

/// Right-side metadata panel: chapter picker, competency checkboxes, difficulty slider.
struct ExerciseMetadataPanel_macOS: View {
    @ObservedObject var viewModel: ExerciseEditorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Difficulty
                difficultySection

                Divider()

                // Chapter
                chapterSection

                // Competencies
                if viewModel.selectedChapterID != nil {
                    competencySection
                }

                Spacer()
            }
            .padding()
        }
        .background(Color(.windowBackgroundColor).opacity(0.5))
    }

    // MARK: - Difficulty

    private var difficultySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Difficulté")
                .font(.headline)

            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        viewModel.difficultyLevel = level
                    } label: {
                        Image(systemName: level <= viewModel.difficultyLevel ? "star.fill" : "star")
                            .foregroundColor(level <= viewModel.difficultyLevel ? .yellow : .gray)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text("Niveau \(viewModel.difficultyLevel)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Chapter

    private var chapterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chapitre")
                .font(.headline)

            Picker("Chapitre", selection: $viewModel.selectedChapterID) {
                Text("Aucun").tag(String?.none)
                ForEach(viewModel.availableChapters) { chapter in
                    Text(chapter.name).tag(Optional(chapter.id))
                }
            }
            .labelsHidden()
        }
    }

    // MARK: - Competencies

    private var competencySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Compétences")
                .font(.headline)

            if let chapterID = viewModel.selectedChapterID {
                let competencies = viewModel.competencies(for: chapterID)
                if competencies.isEmpty {
                    Text("Aucune compétence dans ce chapitre.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(competencies) { competency in
                        if let compID = competency.id {
                            Toggle(
                                competency.label,
                                isOn: Binding(
                                    get: { viewModel.selectedCompetencyIDs.contains(compID) },
                                    set: { isOn in
                                        if isOn {
                                            viewModel.selectedCompetencyIDs.insert(compID)
                                        } else {
                                            viewModel.selectedCompetencyIDs.remove(compID)
                                        }
                                    }
                                )
                            )
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            }
        }
    }
}
