//
//  DiagnosisViews.swift
//  MathClass
//
//  The teacher's diagnosis on the skill taxonomy: one student (what to
//  work on, with the mistakes as evidence), one domain (who struggles on
//  which skill) and the whole class (priorities and a competency map).
//  Built by SkillDiagnosis from the graded copies.
//

import SwiftUI

// MARK: - Shared data

/// Everything the diagnosis views need for one class.
struct ClassDiagnosis {
    let students: [Student]
    let perStudent: [String: StudentSkills]
    let classSkills: [SkillDiagnosis.ClassSkill]
    let exercises: [String: Exercise]

    @MainActor
    init(viewModel: TeacherViewModel, submissions: [Submission], classID: String?) {
        let students = (classID.map { viewModel.studentsInClass($0) } ?? viewModel.studentRepo.students)
            .sorted { ($0.lastName, $0.firstName) < ($1.lastName, $1.firstName) }
        let ids = Set(students.compactMap(\.id))
        var exercises: [String: Exercise] = [:]
        var skills: [String: [String]] = [:]
        for exercise in viewModel.exercises {
            guard let id = exercise.id else { continue }
            exercises[id] = exercise
            skills[id] = exercise.skillIDs ?? []
        }
        let perStudent = SkillDiagnosis.build(
            submissions: submissions.filter { ids.contains($0.studentID) },
            exerciseSkills: skills
        )
        self.students = students
        self.perStudent = perStudent
        self.classSkills = SkillDiagnosis.classSkills(perStudent)
        self.exercises = exercises
    }

    func name(_ studentID: String) -> String {
        students.first { $0.id == studentID }?.firstName ?? "?"
    }

    /// Domains with evidence, in taxonomy order.
    var domainsWithData: [TaxonomyNode] {
        let used = Set(classSkills.compactMap { Taxonomy.shared.skill($0.skillID)?.domain.id })
        return Taxonomy.shared.domains.filter { used.contains($0.id) }
    }

    /// Competencies with evidence, in taxonomy order.
    var competenciesWithData: [TaxonomyNode] {
        let used = Set(classSkills.compactMap { Taxonomy.shared.skill($0.skillID)?.competency.id })
        return Taxonomy.shared.domains
            .flatMap { Taxonomy.shared.competenciesByDomain[$0.id] ?? [] }
            .filter { used.contains($0.id) }
    }
}

extension Mastery {
    var color: Color {
        switch self {
        case .notMastered: return .red
        case .fragile: return .orange
        case .toConfirm: return .gray
        case .mastered: return .green
        }
    }
}

/// Colour of a success rate (competency or domain level).
private func rateColor(_ successes: Int, _ total: Int) -> Color {
    guard total > 0 else { return .gray.opacity(0.15) }
    let rate = Double(successes) / Double(total)
    if rate >= 0.8 { return .green }
    if rate >= 0.5 { return .orange }
    return .red
}

private struct MasteryChip: View {
    let mastery: Mastery
    var body: some View {
        Text(mastery.label)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(mastery.color.opacity(0.15))
            .foregroundColor(mastery.color)
            .cornerRadius(4)
    }
}

private struct RateBar: View {
    let successes: Int
    let total: Int
    var body: some View {
        HStack(spacing: 6) {
            ProgressView(value: Double(successes), total: Double(max(total, 1)))
                .tint(rateColor(successes, total))
                .frame(width: 90)
            Text("\(successes)/\(total)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - One student

struct StudentDiagnosisView: View {
    let data: ClassDiagnosis
    @State private var selectedStudentID: String?

    var body: some View {
        SplitLayout {
            List {
                ForEach(data.students) { student in
                    Button {
                        selectedStudentID = student.id
                    } label: {
                        DiagnosisStudentRow(data: data, student: student)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selectedStudentID == student.id ? Color.accentColor.opacity(0.15) : nil)
                }
            }
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)

            if let id = selectedStudentID, let student = data.students.first(where: { $0.id == id }) {
                StudentDiagnosisDetail(data: data, student: student, skills: data.perStudent[id] ?? [:])
                    .frame(minWidth: 400, maxWidth: .infinity)
            } else {
                Text("Sélectionnez un élève".tr)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// The two panes side by side, resizable on the Mac.
private struct SplitLayout<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        #if os(macOS)
        HSplitView { content }
        #else
        HStack(spacing: 0) { content }
        #endif
    }
}

private struct DiagnosisStudentRow: View {
    let data: ClassDiagnosis
    let student: Student

    var body: some View {
                let skills = data.perStudent[student.id ?? ""] ?? [:]
                let weak = SkillDiagnosis.weakSkills(skills).count
                let rate = SkillDiagnosis.rate(skills, within: Set(skills.keys))
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(student.fullName).font(.headline)
                        if rate.total > 0 {
                            Text(LocalizationManager.shared.format("%@ %% de réussite", String(Int((Double(rate.successes) / Double(rate.total) * 100).rounded()))))
                                .font(.caption).foregroundColor(.secondary)
                        } else {
                            Text("Aucune copie".tr).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    if weak > 0 {
                        Text(LocalizationManager.shared.format(weak == 1 ? "%@ point à travailler" : "%@ points à travailler", String(weak)))
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
                .contentShape(Rectangle())
    }
}

private struct StudentDiagnosisDetail: View {
    let data: ClassDiagnosis
    let student: Student
    let skills: StudentSkills

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(student.fullName).font(.title2.bold())

                if skills.isEmpty {
                    Text("Pas encore de copie corrigée pour cet élève.".tr).foregroundColor(.secondary)
                } else {
                    weakSection
                    watchSection
                    domainsSection
                    strengthsSection
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var weakSection: some View {
        let weak = SkillDiagnosis.weakSkills(skills)
        VStack(alignment: .leading, spacing: 10) {
            Text("Points à travailler".tr).font(.headline)
            if weak.isEmpty {
                Text("Aucune lacune avérée pour l'instant.".tr).foregroundColor(.secondary)
            }
            ForEach(weak, id: \.skillID) { record in
                SkillFinding(data: data, firstName: student.firstName, record: record)
            }
        }
    }

    @ViewBuilder
    private var watchSection: some View {
        let watch = SkillDiagnosis.toWatch(skills)
        if !watch.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("À surveiller (trop peu de copies pour conclure)".tr).font(.headline)
                ForEach(watch, id: \.skillID) { record in
                    if let skill = Taxonomy.shared.skill(record.skillID) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(skill.competency.label) › \(skill.node.label)").font(.callout)
                        }
                    }
                }
            }
        }
    }

    private var domainsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Par domaine".tr).font(.headline)
            ForEach(Taxonomy.shared.domains, id: \.id) { domain in
                let competencies = (Taxonomy.shared.competenciesByDomain[domain.id] ?? []).filter { competency in
                    (Taxonomy.shared.skillsByCompetency[competency.id] ?? []).contains { skills[$0.id] != nil }
                }
                if !competencies.isEmpty {
                    let domainSkills = Set(competencies.flatMap { (Taxonomy.shared.skillsByCompetency[$0.id] ?? []).map(\.id) })
                    let domainRate = SkillDiagnosis.rate(skills, within: domainSkills)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(domain.label).font(.subheadline.bold())
                            Spacer()
                            RateBar(successes: domainRate.successes, total: domainRate.total)
                        }
                        ForEach(competencies, id: \.id) { competency in
                            HStack(alignment: .top) {
                                Text(competency.label).font(.callout).frame(width: 190, alignment: .leading)
                                FlowChips(records: (Taxonomy.shared.skillsByCompetency[competency.id] ?? []).compactMap { skills[$0.id] })
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.06)))
                }
            }
        }
    }

    @ViewBuilder
    private var strengthsSection: some View {
        let mastered = skills.values.filter { $0.mastery == .mastered }.sorted { $0.skillID < $1.skillID }
        if !mastered.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Points forts".tr).font(.headline)
                ForEach(mastered, id: \.skillID) { record in
                    if let skill = Taxonomy.shared.skill(record.skillID) {
                        Text("\(skill.competency.label) › \(skill.node.label) (\(record.successes)/\(record.total))")
                            .font(.callout).foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

/// A weak skill with its sentence and the copies behind it.
private struct SkillFinding: View {
    let data: ClassDiagnosis
    let firstName: String
    let record: SkillRecord
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                MasteryChip(mastery: record.mastery)
                Text(SkillDiagnosis.sentence(firstName: firstName, record: record))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(expanded ? "Masquer les copies".tr : LocalizationManager.shared.format("Voir les %@ copies", String(record.total))) {
                expanded.toggle()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            if expanded {
                ForEach(Array(record.evidence.sorted { $0.date > $1.date }.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(item.success ? .green : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(data.exercises[item.exerciseID]?.displayTitle ?? item.exerciseID) — \(item.date.appFormatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                            if let type = item.errorType {
                                Text(SkillDiagnosis.errorTypeLabel(type)).font(.caption2).foregroundColor(.orange)
                            }
                        }
                    }
                    .padding(.leading, 12)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(record.mastery.color.opacity(0.06)))
    }
}

/// Skills of a competency as coloured chips.
private struct FlowChips: View {
    let records: [SkillRecord]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(records, id: \.skillID) { record in
                HStack(spacing: 6) {
                    Circle().fill(record.mastery.color).frame(width: 8, height: 8)
                    Text(Taxonomy.shared.skill(record.skillID)?.node.label ?? record.skillID).font(.caption)
                    Text("\(record.successes)/\(record.total)").font(.caption2.monospacedDigit()).foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - One domain

struct DomainDiagnosisView: View {
    let data: ClassDiagnosis
    @State private var domainID: String?

    private var domain: TaxonomyNode? {
        data.domainsWithData.first { $0.id == domainID } ?? data.domainsWithData.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if data.domainsWithData.isEmpty {
                Text("Pas encore de copie corrigée sur des exercices étiquetés.".tr)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Picker("Domaine".tr, selection: Binding(get: { domain?.id ?? "" }, set: { domainID = $0 })) {
                    ForEach(data.domainsWithData, id: \.id) { Text($0.label).tag($0.id) }
                }
                .frame(width: 360)
                .padding(.horizontal)

                if let domain {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(Taxonomy.shared.competenciesByDomain[domain.id] ?? [], id: \.id) { competency in
                                competencySection(competency)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .padding(.top)
    }

    @ViewBuilder
    private func competencySection(_ competency: TaxonomyNode) -> some View {
        let rows = (Taxonomy.shared.skillsByCompetency[competency.id] ?? []).compactMap { skill in
            data.classSkills.first { $0.skillID == skill.id }
        }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                let successes = rows.reduce(0) { $0 + $1.successes }
                let total = rows.reduce(0) { $0 + $1.total }
                HStack {
                    Text(competency.label).font(.headline)
                    Spacer()
                    RateBar(successes: successes, total: total)
                }
                ForEach(rows, id: \.skillID) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(Taxonomy.shared.skill(row.skillID)?.node.label ?? row.skillID).font(.callout.bold())
                            Spacer()
                            RateBar(successes: row.successes, total: row.total)
                        }
                        if !row.notMastered.isEmpty {
                            Text(LocalizationManager.shared.format("Non maîtrisé : %@", row.notMastered.map(data.name).joined(separator: ", ")))
                                .font(.caption).foregroundColor(.red)
                        }
                        if !row.fragile.isEmpty {
                            Text(LocalizationManager.shared.format("Fragile : %@", row.fragile.map(data.name).joined(separator: ", ")))
                                .font(.caption).foregroundColor(.orange)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.05)))
                }
            }
        }
    }
}

// MARK: - The class

struct ClassDiagnosisView: View {
    let data: ClassDiagnosis

    private var priorities: [SkillDiagnosis.ClassSkill] {
        data.classSkills.filter { $0.struggling > 0 }.prefix(6).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                summary
                prioritiesSection
                mapSection
                studentsToHelp
            }
            .padding()
        }
    }

    private var summary: some View {
        let successes = data.classSkills.reduce(0) { $0 + $1.successes }
        let total = data.classSkills.reduce(0) { $0 + $1.total }
        let active = data.perStudent.filter { !$0.value.isEmpty }.count
        return HStack(spacing: 28) {
            SummaryNumber(value: "\(active)/\(data.students.count)", label: "élèves évalués".tr)
            SummaryNumber(value: total > 0 ? "\(Int((Double(successes) / Double(total) * 100).rounded())) %" : "—", label: "de réussite".tr)
            SummaryNumber(value: "\(data.classSkills.count)", label: "savoir-faire observés".tr)
            SummaryNumber(value: "\(data.classSkills.filter { $0.struggling > 0 }.count)", label: "à retravailler".tr)
        }
    }

    private var prioritiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Priorités de la classe".tr).font(.headline)
            if priorities.isEmpty {
                Text("Aucune difficulté partagée pour l'instant.".tr).foregroundColor(.secondary)
            }
            ForEach(priorities, id: \.skillID) { row in
                if let skill = Taxonomy.shared.skill(row.skillID) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("\(skill.competency.label) › \(skill.node.label)").font(.callout.bold())
                            Spacer()
                            RateBar(successes: row.successes, total: row.total)
                        }
                        Text(LocalizationManager.shared.format(
                            row.struggling == 1 ? "%@ élève en difficulté : %@" : "%@ élèves en difficulté : %@",
                            String(row.struggling), (row.notMastered + row.fragile).map(data.name).joined(separator: ", ")
                        ))
                        .font(.caption)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.06)))
                }
            }
        }
    }

    /// Students × competencies, coloured by success rate.
    private var mapSection: some View {
        let competencies = data.competenciesWithData
        return VStack(alignment: .leading, spacing: 8) {
            Text("Carte de la classe".tr).font(.headline)
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 4) {
                    GridRow {
                        Text("").frame(width: 150)
                        ForEach(competencies, id: \.id) { competency in
                            Text(competency.label)
                                .font(.caption2)
                                .frame(width: 84, height: 44, alignment: .bottom)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                        }
                    }
                    ForEach(data.students) { student in
                        let skills = data.perStudent[student.id ?? ""] ?? [:]
                        GridRow {
                            Text(student.fullName).font(.caption).frame(width: 150, alignment: .leading).lineLimit(1)
                            ForEach(competencies, id: \.id) { competency in
                                let ids = Set((Taxonomy.shared.skillsByCompetency[competency.id] ?? []).map(\.id))
                                let rate = SkillDiagnosis.rate(skills, within: ids)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(rate.total > 0 ? rateColor(rate.successes, rate.total).opacity(0.75) : Color.gray.opacity(0.1))
                                    .frame(width: 84, height: 18)
                                    .overlay(Text(rate.total > 0 ? "\(rate.successes)/\(rate.total)" : "").font(.caption2).foregroundColor(.white))
                                    .help(rate.total > 0 ? "\(student.firstName) — \(competency.label) : \(rate.successes)/\(rate.total)" : "")
                            }
                        }
                    }
                }
            }
            HStack(spacing: 14) {
                Legend(color: .green, label: "≥ 80 %")
                Legend(color: .orange, label: "50–79 %")
                Legend(color: .red, label: "< 50 %")
                Legend(color: .gray.opacity(0.3), label: "pas de donnée".tr)
            }
            .font(.caption)
        }
    }

    private var studentsToHelp: some View {
        let ranked = data.students.compactMap { student -> (Student, Int)? in
            let weak = SkillDiagnosis.weakSkills(data.perStudent[student.id ?? ""] ?? [:]).count
            return weak > 0 ? (student, weak) : nil
        }
        .sorted { $0.1 > $1.1 }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Élèves à accompagner".tr).font(.headline)
            if ranked.isEmpty {
                Text("Aucun élève avec des lacunes avérées.".tr).foregroundColor(.secondary)
            }
            ForEach(ranked, id: \.0.id) { student, weak in
                let first = SkillDiagnosis.weakSkills(data.perStudent[student.id ?? ""] ?? [:]).prefix(2)
                    .compactMap { Taxonomy.shared.skill($0.skillID)?.node.label }
                Text("\(student.fullName) — \(LocalizationManager.shared.format(weak == 1 ? "%@ point à travailler" : "%@ points à travailler", String(weak))) : \(first.joined(separator: " ; "))")
                    .font(.callout)
            }
        }
    }
}

private struct SummaryNumber: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading) {
            Text(value).font(.title.bold())
            Text(label).font(.caption).foregroundColor(.secondary)
        }
    }
}

private struct Legend: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 10)
            Text(label)
        }
    }
}
