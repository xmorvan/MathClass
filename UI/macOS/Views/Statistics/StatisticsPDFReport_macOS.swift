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
                Text(generatedAt.appFormatted(date: .long, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Divider()

            switch tab {
            case .perStudent:
                studentDiagnoses
            case .perDomain:
                domainReport
            case .perExercise:
                exerciseTable
            case .perClass:
                classReport
            }
        }
        .padding(36)
        .frame(width: pageWidth, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    // MARK: - Diagnosis

    private var diagnosis: ClassDiagnosis {
        ClassDiagnosis(viewModel: viewModel, submissions: submissions, classID: classID)
    }

    /// Every student: success rate, what to work on (with the typical
    /// mistake), what to watch.
    private var studentDiagnoses: some View {
        let data = diagnosis
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(data.students) { student in
                let skills = data.perStudent[student.id ?? ""] ?? [:]
                let rate = SkillDiagnosis.rate(skills, within: Set(skills.keys))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(student.fullName).font(.headline)
                        Spacer()
                        Text(rate.total > 0 ? percent(Double(rate.successes) / Double(rate.total)) : "—")
                            .font(.callout)
                    }
                    let weak = SkillDiagnosis.weakSkills(skills)
                    if skills.isEmpty {
                        Text("Pas encore de copie corrigée pour cet élève.".tr).font(.caption).foregroundColor(.secondary)
                    } else if weak.isEmpty {
                        Text("Aucune lacune avérée pour l'instant.".tr).font(.caption).foregroundColor(.secondary)
                    }
                    ForEach(weak, id: \.skillID) { record in
                        Text("• " + SkillDiagnosis.sentence(firstName: student.firstName, record: record))
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    let watch = SkillDiagnosis.toWatch(skills).compactMap { Taxonomy.shared.skill($0.skillID)?.node.label }
                    if !watch.isEmpty {
                        Text(LocalizationManager.shared.format("À surveiller : %@", watch.joined(separator: " ; ")))
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                Divider()
            }
        }
    }

    /// Every domain with data: skill by skill, class rate and who struggles.
    private var domainReport: some View {
        let data = diagnosis
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(data.domainsWithData, id: \.id) { domain in
                Text(domain.label).font(.headline)
                ForEach(Taxonomy.shared.competenciesByDomain[domain.id] ?? [], id: \.id) { competency in
                    let rows = (Taxonomy.shared.skillsByCompetency[competency.id] ?? []).compactMap { skill in
                        data.classSkills.first { $0.skillID == skill.id }
                    }
                    if !rows.isEmpty {
                        Text(competency.label).font(.subheadline.bold())
                        ForEach(rows, id: \.skillID) { row in
                            VStack(alignment: .leading, spacing: 2) {
                                tableRow([Taxonomy.shared.skill(row.skillID)?.node.label ?? row.skillID,
                                          "\(row.successes)/\(row.total)", percent(row.rate)])
                                if row.struggling > 0 {
                                    Text(LocalizationManager.shared.format("En difficulté : %@",
                                                                           (row.notMastered + row.fragile).map(data.name).joined(separator: ", ")))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                Divider()
            }
        }
    }

    /// Class summary, priorities and students to help.
    private var classReport: some View {
        let data = diagnosis
        let priorities = data.classSkills.filter { $0.struggling > 0 }.prefix(8)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Priorités de la classe".tr).font(.headline)
            ForEach(Array(priorities), id: \.skillID) { row in
                if let skill = Taxonomy.shared.skill(row.skillID) {
                    VStack(alignment: .leading, spacing: 2) {
                        tableRow(["\(skill.competency.label) › \(skill.node.label)", "\(row.successes)/\(row.total)", percent(row.rate)])
                        Text(LocalizationManager.shared.format("En difficulté : %@",
                                                               (row.notMastered + row.fragile).map(data.name).joined(separator: ", ")))
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            if priorities.isEmpty {
                Text("Aucune difficulté partagée pour l'instant.".tr).foregroundColor(.secondary)
            }
            Divider()
            Text("Élèves à accompagner".tr).font(.headline)
            ForEach(data.students) { student in
                let weak = SkillDiagnosis.weakSkills(data.perStudent[student.id ?? ""] ?? [:])
                if !weak.isEmpty {
                    Text("\(student.fullName) : " + weak.prefix(3).compactMap { Taxonomy.shared.skill($0.skillID)?.node.label }.joined(separator: " ; "))
                        .font(.callout)
                }
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
                    exercise.displayTitle,
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
