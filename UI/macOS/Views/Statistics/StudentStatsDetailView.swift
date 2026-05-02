//
//  StudentStatsDetailView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import SwiftUI

/// Per-student statistics list for macOS.
/// Shows all students with summary stats; select one to see detailed breakdown.
struct StudentStatsListView_macOS: View {
    @ObservedObject var viewModel: TeacherViewModel
    let submissions: [Submission]
    let classID: String?

    @State private var selectedStudentID: String?

    private let statisticsService = StatisticsService.shared

    private var students: [Student] {
        if let classID = classID {
            return viewModel.studentsInClass(classID)
        }
        return viewModel.studentRepo.students
    }

    private var exerciseCompetencyMap: [String: [String]] {
        var map: [String: [String]] = [:]
        for exercise in viewModel.exercises {
            if let id = exercise.id {
                map[id] = exercise.competencyIDs
            }
        }
        return map
    }

    var body: some View {
        HSplitView {
            // Left: student list with summary
            List(selection: $selectedStudentID) {
                ForEach(students) { student in
                    let stats = statisticsService.getStudentStats(
                        studentID: student.id ?? "",
                        submissions: submissions,
                        exerciseCompetencyMap: exerciseCompetencyMap
                    )
                    studentRow(student: student, stats: stats)
                        .tag(student.id)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 280)

            // Right: student detail
            if let studentID = selectedStudentID,
               let student = students.first(where: { $0.id == studentID }) {
                studentDetail(student: student)
            } else {
                Text("Sélectionnez un élève")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Student Row

    private func studentRow(student: Student, stats: StatisticsService.StudentStats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(student.firstName) \(student.lastName)")
                .font(.headline)

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("\(stats.successCount)/\(stats.totalAttempts)")
                        .font(.caption)
                }

                if stats.totalAttempts > 0 {
                    Text(String(format: "%.0f%%", stats.successRate * 100))
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
        }
        .padding(.vertical, 4)
    }

    // MARK: - Student Detail

    private func studentDetail(student: Student) -> some View {
        let stats = statisticsService.getStudentStats(
            studentID: student.id ?? "",
            submissions: submissions,
            exerciseCompetencyMap: exerciseCompetencyMap
        )
        let studentSubmissions = submissions
            .filter { $0.studentID == student.id }
            .sorted { $0.timestamp > $1.timestamp }

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("\(student.firstName) \(student.lastName)")
                        .font(.title2)
                        .bold()
                    Spacer()
                    Text(String(format: "Taux de réussite : %.0f%%", stats.successRate * 100))
                        .font(.headline)
                        .foregroundColor(successRateColor(stats.successRate))
                }

                // Summary cards
                HStack(spacing: 16) {
                    StatCard_macOS(title: "Exercices", value: "\(stats.totalAttempts)")
                    StatCard_macOS(
                        title: "Réussis",
                        value: "\(stats.successCount)",
                        color: .green
                    )
                    StatCard_macOS(
                        title: "Échoués",
                        value: "\(stats.failCount)",
                        color: .red
                    )
                    StatCard_macOS(
                        title: "Temps moyen",
                        value: formatDuration(stats.averageTime)
                    )
                }

                Divider()

                // Competency breakdown
                if !stats.competencyRates.isEmpty {
                    Text("Par compétence")
                        .font(.headline)

                    ForEach(Array(stats.competencyRates.keys.sorted()), id: \.self) { competencyID in
                        if let rate = stats.competencyRates[competencyID] {
                            let competencyLabel = findCompetencyLabel(competencyID)
                            HStack {
                                Text(competencyLabel)
                                    .font(.body)
                                Spacer()
                                Text(String(format: "%.0f%%", rate * 100))
                                    .font(.body)
                                    .bold()
                                    .foregroundColor(successRateColor(rate))
                                ProgressView(value: rate)
                                    .frame(width: 100)
                                    .tint(successRateColor(rate))
                            }
                        }
                    }
                }

                Divider()

                // Recent submissions
                Text("Soumissions récentes")
                    .font(.headline)

                ForEach(studentSubmissions.prefix(20), id: \.id) { submission in
                    submissionRow(submission: submission)
                }
            }
            .padding()
        }
    }

    private func submissionRow(submission: Submission) -> some View {
        let exerciseTitle = viewModel.exercises.first { $0.id == submission.exerciseID }?.title ?? "Exercice inconnu"

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(exerciseTitle)
                    .font(.body)
                Text("Essai \(submission.attemptNumber) — \(submission.timestamp.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let result = submission.finalResult {
                HStack(spacing: 4) {
                    Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.isSuccess ? .green : .red)
                    Text(result.displayName)
                        .font(.caption)
                }
            } else {
                Text("En attente")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(formatDuration(submission.timeSpent))
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
    }

    // MARK: - Helpers

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
