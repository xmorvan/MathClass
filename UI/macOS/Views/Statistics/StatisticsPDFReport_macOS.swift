//
//  StatisticsPDFReport_macOS.swift
//  MathClass
//
//  Render-to-PDF wrapper for the macOS statistics views. ImageRenderer
//  rasterizes nothing inside ScrollView / List / HSplitView, so the
//  report lays the same numbers out as plain stacks: a letter-wide page
//  whose height grows with the content (PDFExporter slices it into pages).
//

import SwiftUI

struct StatisticsPDFReport_macOS: View {
    let title: String
    let generatedAt: Date
    let tab: StatisticsView_macOS.StatTab
    let viewModel: TeacherViewModel
    let submissions: [Submission]
    let classID: String?

    private let pageWidth: CGFloat = 612   // 8.5" @ 72 DPI
    private let statisticsService = StatisticsService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2)
                    .bold()
                Text(generatedAt.formatted(date: .long, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Divider()

            switch tab {
            case .perStudent:
                studentTable
            case .perExercise:
                exerciseTable
            case .perClass:
                ClassOverviewView_macOS(
                    viewModel: viewModel,
                    submissions: submissions,
                    classID: classID,
                    scrolls: false
                )
            }
        }
        .padding(36)
        .frame(width: pageWidth, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    // MARK: - Per student

    private var students: [Student] {
        if let classID = classID {
            return viewModel.studentsInClass(classID)
        }
        return viewModel.studentRepo.students
    }

    private var exerciseCompetencyMap: [String: [String]] {
        var map: [String: [String]] = [:]
        for exercise in viewModel.exercises {
            if let id = exercise.id { map[id] = exercise.competencyIDs }
        }
        return map
    }

    private var studentTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            tableHeader(["Élève".tr, "Exercices".tr, "Réussis".tr, "Taux de réussite".tr, "Temps moyen".tr])
            ForEach(students) { student in
                let stats = statisticsService.getStudentStats(
                    studentID: student.id ?? "",
                    submissions: submissions,
                    exerciseCompetencyMap: exerciseCompetencyMap
                )
                tableRow([
                    student.fullName,
                    "\(stats.totalAttempts)",
                    "\(stats.successCount)",
                    stats.totalAttempts > 0 ? percent(stats.successRate) : "—",
                    stats.totalAttempts > 0 ? duration(stats.averageTime) : "—"
                ])
                Divider()
            }
        }
    }

    // MARK: - Per exercise

    private var exerciseTable: some View {
        let exerciseIDs = Set(submissions.map(\.exerciseID))
        let exercises = viewModel.exercises.filter { exerciseIDs.contains($0.id ?? "") }
        return VStack(alignment: .leading, spacing: 6) {
            tableHeader(["Exercice".tr, "Soumissions".tr, "Taux de réussite".tr, "Temps moyen".tr])
            ForEach(exercises) { exercise in
                let stats = statisticsService.getExerciseStats(
                    exerciseID: exercise.id ?? "",
                    submissions: submissions
                )
                tableRow([
                    exercise.title,
                    "\(stats.totalSubmissions)",
                    percent(stats.successRate),
                    duration(stats.averageTime)
                ])
                Divider()
            }
            if exercises.isEmpty {
                Text("Aucune donnée".tr)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Table helpers

    private func tableHeader(_ columns: [String]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                Text(column)
                    .font(.caption)
                    .bold()
                    .foregroundColor(.secondary)
                    .frame(maxWidth: index == 0 ? .infinity : nil, alignment: .leading)
                    .frame(width: index == 0 ? nil : 90, alignment: .trailing)
            }
        }
    }

    private func tableRow(_ columns: [String]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                Text(column)
                    .font(.callout)
                    .lineLimit(2)
                    .frame(maxWidth: index == 0 ? .infinity : nil, alignment: .leading)
                    .frame(width: index == 0 ? nil : 90, alignment: .trailing)
            }
        }
    }

    private func percent(_ rate: Double) -> String {
        String(format: "%.0f%%", rate * 100)
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return minutes > 0 ? "\(minutes)m \(secs)s" : "\(secs)s"
    }
}
