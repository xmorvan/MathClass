//
//  ClassOverviewView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import SwiftUI

/// Per-class overview statistics for macOS.
/// Shows overall success rates, weakest competencies, students in difficulty,
/// and average times.
struct ClassOverviewView_macOS: View {
    @ObservedObject var viewModel: TeacherViewModel
    let submissions: [Submission]
    let classID: String?

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
        let stats = statisticsService.getClassStats(
            classID: classID ?? "",
            studentIDs: students.compactMap { $0.id },
            submissions: submissions,
            exerciseCompetencyMap: exerciseCompetencyMap
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Summary
                overviewHeader(stats: stats)

                Divider()

                // Weakest competencies
                weakestCompetenciesSection(stats: stats)

                Divider()

                // Students in difficulty
                studentsInDifficultySection(stats: stats)

                Divider()

                // All students ranking
                studentRankingSection()
            }
            .padding()
        }
    }

    // MARK: - Overview Header

    private func overviewHeader(stats: StatisticsService.ClassStats) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let classID = classID,
               let classroom = viewModel.classes.first(where: { $0.id == classID }) {
                Text("Vue d'ensemble — \(classroom.name)")
                    .font(.title2)
                    .bold()
            } else {
                Text("Vue d'ensemble".tr)
                    .font(.title2)
                    .bold()
            }

            HStack(spacing: 20) {
                StatCard_macOS(
                    title: "Élèves",
                    value: "\(stats.totalStudents)"
                )
                StatCard_macOS(
                    title: "Soumissions",
                    value: "\(stats.totalSubmissions)"
                )
                StatCard_macOS(
                    title: "Taux de réussite",
                    value: String(format: "%.0f%%", stats.overallSuccessRate * 100),
                    color: successRateColor(stats.overallSuccessRate)
                )
                StatCard_macOS(
                    title: "Temps moyen",
                    value: formatDuration(stats.averageTime)
                )
                StatCard_macOS(
                    title: "Élèves en difficulté",
                    value: "\(stats.studentsInDifficulty.count)",
                    color: stats.studentsInDifficulty.isEmpty ? .green : .red
                )
            }
        }
    }

    // MARK: - Weakest Competencies

    @ViewBuilder
    private func weakestCompetenciesSection(stats: StatisticsService.ClassStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compétences les plus faibles".tr)
                .font(.headline)

            if stats.weakestCompetencies.isEmpty {
                Text("Aucune donnée de compétence disponible.".tr)
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                ForEach(stats.weakestCompetencies.prefix(10), id: \.competencyID) { comp in
                    let label = findCompetencyLabel(comp.competencyID)
                    HStack {
                        Text(label)
                            .font(.body)
                            .lineLimit(1)

                        Spacer()

                        ProgressView(value: comp.successRate)
                            .frame(width: 150)
                            .tint(successRateColor(comp.successRate))

                        Text(String(format: "%.0f%%", comp.successRate * 100))
                            .font(.caption)
                            .bold()
                            .foregroundColor(successRateColor(comp.successRate))
                            .frame(width: 45, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        comp.successRate < 0.4
                            ? Color.red.opacity(0.05)
                            : Color.clear
                    )
                    .cornerRadius(6)
                }
            }
        }
    }

    // MARK: - Students in Difficulty

    @ViewBuilder
    private func studentsInDifficultySection(stats: StatisticsService.ClassStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Élèves en difficulté".tr)
                    .font(.headline)
                Text("(< 40% de réussite)".tr)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if stats.studentsInDifficulty.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Aucun élève en difficulté !".tr)
                        .foregroundColor(.green)
                }
                .font(.body)
            } else {
                ForEach(stats.studentsInDifficulty, id: \.studentID) { item in
                    let student = students.first { $0.id == item.studentID }
                    if let student = student {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                            Text("\(student.firstName) \(student.lastName)")
                                .font(.body)
                            Spacer()
                            Text(String(format: "%.0f%%", item.successRate * 100))
                                .font(.headline)
                                .foregroundColor(.red)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color.red.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    // MARK: - Student Ranking

    private func studentRankingSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Classement des élèves".tr)
                .font(.headline)

            let allStats = students.map { student in
                statisticsService.getStudentStats(
                    studentID: student.id ?? "",
                    submissions: submissions,
                    exerciseCompetencyMap: exerciseCompetencyMap
                )
            }.sorted { $0.successRate > $1.successRate }

            ForEach(Array(allStats.enumerated()), id: \.element.studentID) { index, stats in
                let student = students.first { $0.id == stats.studentID }
                if let student = student {
                    HStack {
                        Text("\(index + 1).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 30, alignment: .trailing)

                        Text("\(student.firstName) \(student.lastName)")
                            .font(.body)

                        Spacer()

                        Text("\(stats.successCount)/\(stats.totalAttempts)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if stats.totalAttempts > 0 {
                            ProgressView(value: stats.successRate)
                                .frame(width: 80)
                                .tint(successRateColor(stats.successRate))

                            Text(String(format: "%.0f%%", stats.successRate * 100))
                                .font(.caption)
                                .bold()
                                .foregroundColor(successRateColor(stats.successRate))
                                .frame(width: 45, alignment: .trailing)
                        } else {
                            Text("—")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 125, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
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
