//
//  ExercisesListView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.11.2024.
//

import SwiftUI

/// Teacher's exercise list for iPad.
/// Groups exercises by chapter when chapters exist.
struct ExercisesListView: View {
    @ObservedObject var viewModel: TeacherViewModel
    @State private var showingAddExercise = false
    @State private var selectedExercise: Exercise?
    @State private var exerciseToDelete: Exercise?

    var body: some View {
        List {
            if groupedExercises.isEmpty {
                Text("Aucun exercice créé.".tr)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(groupedExercises, id: \.title) { section in
                    Section(header: Text(section.title)) {
                        ForEach(section.exercises) { exercise in
                            ExerciseRow(exercise: exercise)
                                .onTapGesture {
                                    selectedExercise = exercise
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        exerciseToDelete = exercise
                                    } label: {
                                        Label("Supprimer".tr, systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddExercise = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddExercise) {
            AddExerciseView(viewModel: viewModel)
        }
        .sheet(item: $selectedExercise) { exercise in
            EditExerciseView(viewModel: viewModel, exercise: exercise)
        }
        .alert(
            "Supprimer l'exercice ?".tr,
            isPresented: Binding(get: { exerciseToDelete != nil }, set: { if !$0 { exerciseToDelete = nil } })
        ) {
            Button("Annuler".tr, role: .cancel) { exerciseToDelete = nil }
            Button("Supprimer".tr, role: .destructive) {
                if let id = exerciseToDelete?.id {
                    Task { try? await viewModel.deleteExercise(id: id) }
                }
                exerciseToDelete = nil
            }
        } message: {
            Text("L'exercice sera retiré de votre bibliothèque.".tr)
        }
    }

    // MARK: - Grouping

    private struct ExerciseSection {
        let title: String
        let exercises: [Exercise]
    }

    private var groupedExercises: [ExerciseSection] {
        let chapters = viewModel.chapters
        var sections: [ExerciseSection] = []

        // Group by chapter
        for chapter in chapters.sorted(by: { $0.order < $1.order }) {
            let matching = viewModel.exercises.filter { $0.chapterID == chapter.id }
            if !matching.isEmpty {
                sections.append(ExerciseSection(title: chapter.name, exercises: matching))
            }
        }

        // Everything not shown above: no chapter, or a chapter of a class
        // whose chapters aren't loaded right now (chapters are per class).
        // Filtering on `chapterID == nil` alone made those exercises vanish.
        let shownChapterIDs = Set(chapters.compactMap(\.id))
        let uncategorized = viewModel.exercises.filter { exercise in
            guard let chapterID = exercise.chapterID, !chapterID.isEmpty else { return true }
            return !shownChapterIDs.contains(chapterID)
        }
        if !uncategorized.isEmpty {
            sections.append(ExerciseSection(title: "Sans chapitre".tr, exercises: uncategorized))
        }

        // If no chapters at all, show flat list
        if sections.isEmpty && !viewModel.exercises.isEmpty {
            sections.append(ExerciseSection(title: "Tous les exercices".tr, exercises: viewModel.exercises))
        }

        return sections
    }
}

/// Row displaying exercise info with difficulty badge.
struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(exercise.title)
                    .font(.headline)
                Spacer()
                difficultyBadge
            }
            if !exercise.statement.isEmpty {
                Text(exercise.statement.latexPlainPreview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var difficultyBadge: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { level in
                Image(systemName: level <= exercise.difficultyLevel ? "star.fill" : "star")
                    .foregroundColor(level <= exercise.difficultyLevel ? .yellow : .gray.opacity(0.3))
                    .font(.system(size: 10))
            }
        }
    }
}
