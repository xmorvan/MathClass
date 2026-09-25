//
//  ExerciseErrorAnalysisView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import SwiftUI

/// Per-exercise statistics list for macOS.
/// Shows exercises with overall success rates; select one to see grouped errors by step.
struct ExerciseStatsListView_macOS: View {
    @ObservedObject var viewModel: TeacherViewModel
    let submissions: [Submission]

    @State private var selectedExerciseID: String?

    private let statisticsService = StatisticsService.shared

    var body: some View {
        HSplitView {
            // Left: exercise list with success rates
            List(selection: $selectedExerciseID) {
                ForEach(viewModel.exercises) { exercise in
                    let stats = statisticsService.getExerciseStats(
                        exerciseID: exercise.id ?? "",
                        submissions: submissions
                    )
                    exerciseRow(exercise: exercise, stats: stats)
                        .tag(exercise.id)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 300)

            // Right: exercise error analysis
            if let exerciseID = selectedExerciseID,
               let exercise = viewModel.exercises.first(where: { $0.id == exerciseID }) {
                exerciseDetail(exercise: exercise)
            } else {
                Text("Sélectionnez un exercice pour voir l'analyse des erreurs".tr)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Exercise Row

    private func exerciseRow(exercise: Exercise, stats: StatisticsService.ExerciseStats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.title)
                .font(.headline)

            HStack(spacing: 12) {
                Text(LocalizationManager.shared.format(stats.totalSubmissions == 1 ? "%@ soumission" : "%@ soumissions", String(stats.totalSubmissions)))
                    .font(.caption)
                    .foregroundColor(.secondary)

                if stats.totalSubmissions > 0 {
                    Text(String(format: "%.0f%% réussite", stats.successRate * 100))
                        .font(.caption)
                        .bold()
                        .foregroundColor(successRateColor(stats.successRate))
                }
            }

            // Difficulty stars
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { level in
                    Image(systemName: level <= exercise.difficultyLevel ? "star.fill" : "star")
                        .foregroundColor(level <= exercise.difficultyLevel ? .yellow : .gray.opacity(0.3))
                        .font(.system(size: 10))
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Exercise Detail (Error Analysis)

    private func exerciseDetail(exercise: Exercise) -> some View {
        let stats = statisticsService.getExerciseStats(
            exerciseID: exercise.id ?? "",
            submissions: submissions
        )

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text(exercise.title)
                            .font(.title2)
                            .bold()
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { level in
                                Image(systemName: level <= exercise.difficultyLevel ? "star.fill" : "star")
                                    .foregroundColor(level <= exercise.difficultyLevel ? .yellow : .gray.opacity(0.3))
                                    .font(.caption)
                            }
                        }
                    }
                    Spacer()
                    Text(String(format: "%.0f%% réussite", stats.successRate * 100))
                        .font(.title3)
                        .bold()
                        .foregroundColor(successRateColor(stats.successRate))
                }

                // Summary cards
                HStack(spacing: 16) {
                    StatCard_macOS(title: "Soumissions", value: "\(stats.totalSubmissions)")
                    StatCard_macOS(
                        title: "Taux de réussite",
                        value: String(format: "%.0f%%", stats.successRate * 100),
                        color: successRateColor(stats.successRate)
                    )
                    StatCard_macOS(
                        title: "Temps moyen",
                        value: formatDuration(stats.averageTime)
                    )
                }

                // Exercise statement preview
                Text("Énoncé".tr)
                    .font(.headline)
                KaTeXView(content: exercise.statement, mode: .preview, fontSize: 16, minHeight: 60)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)

                Divider()

                // Step error analysis — the killer feature
                if !stats.stepErrorCounts.isEmpty {
                    stepErrorAnalysis(stats: stats)
                } else if stats.totalSubmissions > 0 {
                    Text("Aucune erreur détectée dans les étapes.".tr)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }

    // MARK: - Step Error Analysis (Killer Feature)

    @ViewBuilder
    private func stepErrorAnalysis(stats: StatisticsService.ExerciseStats) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Analyse des erreurs par étape".tr)
                .font(.headline)

            Text("Les étapes les plus problématiques sont mises en évidence.".tr)
                .font(.caption)
                .foregroundColor(.secondary)

            let sortedSteps = stats.stepErrorCounts.sorted { $0.value > $1.value }

            ForEach(sortedSteps, id: \.key) { stepIndex, errorCount in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(LocalizationManager.shared.format("Étape %@", String(stepIndex + 1)))
                            .font(.headline)
                            .foregroundColor(.red)

                        Spacer()

                        Text(LocalizationManager.shared.format(errorCount == 1 ? "%@ élève en erreur" : "%@ élèves en erreur", String(errorCount)))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                    }

                    // Common wrong expressions
                    if let errors = stats.commonErrors[stepIndex], !errors.isEmpty {
                        Text("Expressions erronées les plus fréquentes :".tr)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach(errors.prefix(5), id: \.expression) { error in
                            HStack {
                                KaTeXView(
                                    content: "$\(error.expression)$",
                                    mode: .preview,
                                    fontSize: 14,
                                    minHeight: 30
                                )
                                .frame(maxWidth: 300, alignment: .leading)

                                Spacer()

                                Text("×\(error.count)")
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.04))
                            .cornerRadius(4)
                        }
                    }

                    // Students who failed at this step
                    if let failedStudents = stats.failedStudentsByStep[stepIndex], !failedStudents.isEmpty {
                        DisclosureGroup("Élèves concernés (\(failedStudents.count))") {
                            ForEach(failedStudents, id: \.self) { studentID in
                                let student = viewModel.studentRepo.students.first { $0.id == studentID }
                                if let student = student {
                                    Text("\(student.firstName) \(student.lastName)")
                                        .font(.caption)
                                }
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Helpers

    private func successRateColor(_ rate: Double) -> Color {
        if rate >= 0.7 { return .green }
        if rate >= 0.4 { return .orange }
        return .red
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return minutes > 0 ? "\(minutes)m \(secs)s" : "\(secs)s"
    }
}
