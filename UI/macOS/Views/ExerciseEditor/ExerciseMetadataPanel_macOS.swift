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
            Text("Difficulté".tr)
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

                Text(LocalizationManager.shared.format("Niveau %@", String(viewModel.difficultyLevel)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Chapter

    private var chapterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Chapters belong to a class: choose which class's chapters to
            // list (after a relaunch none was selected and only "None" showed).
            ClassPickerBar(viewModel: viewModel.teacherViewModel)

            Text("Chapitre".tr)
                .font(.headline)

            Picker("Chapitre".tr, selection: $viewModel.selectedChapterID) {
                Text("Aucun".tr).tag(String?.none)
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
            Text("Compétences".tr)
                .font(.headline)

            if let chapterID = viewModel.selectedChapterID {
                let competencies = viewModel.competencies(for: chapterID)
                if competencies.isEmpty {
                    Text("Aucune compétence dans ce chapitre.".tr)
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
