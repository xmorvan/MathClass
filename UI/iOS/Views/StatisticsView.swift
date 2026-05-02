//
//  StatisticsView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.11.2024.
//

import SwiftUI

/// Teacher statistics dashboard for iPad.
/// Three tabs: Per-student, Per-exercise, Per-class.
struct StatisticsView: View {
    @ObservedObject var viewModel: TeacherViewModel
    @State private var selectedTab: StatTab = .perStudent
    @State private var selectedClassID: String?
    @State private var isLoadingStats: Bool = false
    @State private var submissions: [Submission] = []

    enum StatTab: String, CaseIterable {
        case perStudent = "Par élève"
        case perExercise = "Par exercice"
        case perClass = "Par classe"
    }

    private let statisticsService = StatisticsService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            filterBar

            Divider()

            if isLoadingStats {
                ProgressView("Chargement des statistiques…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if submissions.isEmpty && selectedClassID != nil {
                emptyState
            } else {
                switch selectedTab {
                case .perStudent:
                    studentStatsList
                case .perExercise:
                    exerciseStatsList
                case .perClass:
                    classOverview
                }
            }
        }
        .onChange(of: selectedClassID) { _, _ in
            Task { await loadSubmissions() }
        }
        .onAppear {
            if selectedClassID == nil, let first = viewModel.classes.first {
                selectedClassID = first.id
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack {
            Picker("Classe", selection: $selectedClassID) {
                Text("Toutes").tag(nil as String?)
                ForEach(viewModel.classes) { classroom in
                    Text(classroom.name).tag(classroom.id as String?)
                }
            }
            .frame(width: 150)

            Picker("Vue", selection: $selectedTab) {
                ForEach(StatTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Button {
                Task { await loadSubmissions() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Aucune donnée")
                .font(.headline)
            Text("Les statistiques apparaîtront lorsque des élèves auront soumis des travaux.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Per-Student

    private var studentStatsList: some View {
        let students = selectedClassID != nil
            ? viewModel.studentsInClass(selectedClassID!)
            : viewModel.studentRepo.students
        let exerciseCompetencyMap = buildExerciseCompetencyMap()

        return List {
            ForEach(students) { student in
                let stats = statisticsService.getStudentStats(
                    studentID: student.id ?? "",
                    submissions: submissions,
                    exerciseCompetencyMap: exerciseCompetencyMap
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(student.firstName) \(student.lastName)")
                        .font(.headline)

                    HStack(spacing: 12) {
                        Label(
                            "\(stats.successCount)/\(stats.totalAttempts)",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundColor(.green)
                        .font(.caption)

                        if stats.totalAttempts > 0 {
                            Text(String(format: "%.0f%%", stats.successRate * 100))
                                .font(.caption)
                                .bold()
                                .foregroundColor(successRateColor(stats.successRate))
                        }

                        if stats.averageTime > 0 {
                            Label(
                                formatDuration(stats.averageTime),
                                systemImage: "clock"
                            )
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        }
                    }

                    if stats.totalAttempts > 0 {
                        ProgressView(value: stats.successRate)
                            .tint(successRateColor(stats.successRate))
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Per-Exercise

    private var exerciseStatsList: some View {
        List {
            ForEach(viewModel.exercises) { exercise in
                let stats = statisticsService.getExerciseStats(
                    exerciseID: exercise.id ?? "",
                    submissions: submissions
                )
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(exercise.title)
                            .font(.headline)
                        Spacer()
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { level in
                                Image(systemName: level <= exercise.difficultyLevel ? "star.fill" : "star")
                                    .foregroundColor(level <= exercise.difficultyLevel ? .yellow : .gray.opacity(0.3))
                                    .font(.system(size: 10))
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Text("\(stats.totalSubmissions) soumission\(stats.totalSubmissions != 1 ? "s" : "")")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if stats.totalSubmissions > 0 {
                            Text(String(format: "%.0f%% réussite", stats.successRate * 100))
                                .font(.caption)
                                .bold()
                                .foregroundColor(successRateColor(stats.successRate))
                        }

                        if stats.averageTime > 0 {
                            Text(formatDuration(stats.averageTime))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Step errors summary
                    if !stats.stepErrorCounts.isEmpty {
                        let totalErrors = stats.stepErrorCounts.values.reduce(0, +)
                        let worstStep = stats.stepErrorCounts.max { $0.value < $1.value }
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.red)
                                .font(.caption2)
                            Text("\(totalErrors) erreur\(totalErrors != 1 ? "s" : "")")
                                .font(.caption2)
                                .foregroundColor(.red)
                            if let worst = worstStep {
                                Text("(étape \(worst.key + 1) : \(worst.value) élèves)")
                                    .font(.caption2)
                                    .foregroundColor(.red.opacity(0.7))
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Per-Class

    private var classOverview: some View {
        let students = selectedClassID != nil
            ? viewModel.studentsInClass(selectedClassID!)
            : viewModel.studentRepo.students
        let exerciseCompetencyMap = buildExerciseCompetencyMap()
        let stats = statisticsService.getClassStats(
            classID: selectedClassID ?? "",
            studentIDs: students.compactMap { $0.id },
            submissions: submissions,
            exerciseCompetencyMap: exerciseCompetencyMap
        )

        return List {
            Section("Résumé") {
                StatSummaryRow(title: "Élèves", value: "\(stats.totalStudents)", icon: "person.3")
                StatSummaryRow(title: "Soumissions", value: "\(stats.totalSubmissions)", icon: "doc.text")
                StatSummaryRow(
                    title: "Taux de réussite",
                    value: String(format: "%.0f%%", stats.overallSuccessRate * 100),
                    icon: "chart.bar",
                    color: successRateColor(stats.overallSuccessRate)
                )
                StatSummaryRow(
                    title: "Temps moyen",
                    value: formatDuration(stats.averageTime),
                    icon: "clock"
                )
            }

            if !stats.weakestCompetencies.isEmpty {
                Section("Compétences les plus faibles") {
                    ForEach(stats.weakestCompetencies.prefix(5), id: \.competencyID) { comp in
                        HStack {
                            Text(findCompetencyLabel(comp.competencyID))
                                .font(.body)
                            Spacer()
                            Text(String(format: "%.0f%%", comp.successRate * 100))
                                .font(.caption)
                                .bold()
                                .foregroundColor(successRateColor(comp.successRate))
                        }
                    }
                }
            }

            if !stats.studentsInDifficulty.isEmpty {
                Section("Élèves en difficulté (< 40%)") {
                    ForEach(stats.studentsInDifficulty, id: \.studentID) { item in
                        let student = students.first { $0.id == item.studentID }
                        if let student = student {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                                Text("\(student.firstName) \(student.lastName)")
                                Spacer()
                                Text(String(format: "%.0f%%", item.successRate * 100))
                                    .font(.headline)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Helpers

    private func loadSubmissions() async {
        isLoadingStats = true
        do {
            var allSubmissions: [Submission] = []
            let assignmentsToLoad = selectedClassID != nil
                ? viewModel.assignments.filter { $0.classID == selectedClassID }
                : viewModel.assignments

            for assignment in assignmentsToLoad {
                guard let id = assignment.id else { continue }
                let subs = try await viewModel.submissionRepo.getSubmissions(assignmentID: id)
                allSubmissions.append(contentsOf: subs)
            }
            self.submissions = allSubmissions
        } catch {
            print("Erreur chargement statistiques: \(error.localizedDescription)")
        }
        isLoadingStats = false
    }

    private func buildExerciseCompetencyMap() -> [String: [String]] {
        var map: [String: [String]] = [:]
        for exercise in viewModel.exercises {
            if let id = exercise.id { map[id] = exercise.competencyIDs }
        }
        return map
    }

    private func findCompetencyLabel(_ competencyID: String) -> String {
        for chapter in viewModel.chapters {
            if let comp = viewModel.chapterRepo.competencies[chapter.id ?? ""]?
                .first(where: { $0.id == competencyID }) {
                return comp.label
            }
        }
        return competencyID
    }

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

// MARK: - Summary Row

private struct StatSummaryRow: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = .accentColor

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)
            Text(title)
            Spacer()
            Text(value)
                .font(.headline)
                .foregroundColor(color)
        }
    }
}

/// Simple stat summary card (kept for backward compatibility).
struct StatSummaryCard: View {
    let title: String
    let count: Int
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
            Text("\(count)")
                .font(.title)
                .bold()
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 100, height: 100)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}
