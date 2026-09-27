//
//  SkillDiagnosis.swift
//  MathClass
//
//  The teacher's diagnosis, skill by skill of the taxonomy: what each
//  student masters or not, with the copies and the typical mistakes as
//  evidence, and the same rolled up for the class and for a domain.
//
//  Evidence: every graded copy (first and second tries alike).
//  - A right copy is a success for each skill of its exercise.
//  - A wrong copy is a failure for each skill the correction diagnosed on
//    its wrong steps (steps that only follow from an earlier mistake do not
//    count); without a diagnosis, for each skill of its exercise.
//

import Foundation

enum Mastery: Int, Comparable {
    case notMastered = 0
    case fragile = 1
    /// Too few copies for a verdict.
    case toConfirm = 2
    case mastered = 3

    static func < (lhs: Mastery, rhs: Mastery) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .notMastered: return "Non maîtrisé".tr
        case .fragile: return "Fragile".tr
        case .toConfirm: return "À confirmer".tr
        case .mastered: return "Maîtrisé".tr
        }
    }

    /// Needs the teacher's attention.
    var isWeak: Bool { self == .notMastered || self == .fragile }
}

struct SkillEvidence: Hashable {
    let submissionID: String?
    let exerciseID: String
    let date: Date
    let success: Bool
    let attempt: Int
    let errorType: String?
    let note: String?
}

struct SkillRecord: Hashable {
    let skillID: String
    private(set) var evidence: [SkillEvidence] = []

    init(skillID: String) { self.skillID = skillID }

    mutating func add(_ item: SkillEvidence) {
        evidence.append(item)
    }

    var successes: Int { evidence.filter(\.success).count }
    var failures: Int { evidence.count - successes }
    var total: Int { evidence.count }
    var rate: Double { total > 0 ? Double(successes) / Double(total) : 0 }

    var mastery: Mastery {
        // Two failures out of two or three is already a verdict; otherwise
        // three copies are needed (one slip fixed at the second try is not
        // a gap).
        if failures >= 2 && rate < 0.5 { return .notMastered }
        if total < 3 { return .toConfirm }
        if rate >= 0.8 { return .mastered }
        if rate >= 0.5 { return .fragile }
        return .notMastered
    }

    /// Failures, most recent first, with the correction's note.
    var mistakes: [SkillEvidence] {
        evidence.filter { !$0.success }.sorted { $0.date > $1.date }
    }

    /// Most frequent error type among the failures.
    var typicalErrorType: String? {
        let types = mistakes.compactMap(\.errorType)
        return Dictionary(grouping: types, by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }
}

/// One student's records, skill ID → record.
typealias StudentSkills = [String: SkillRecord]

enum SkillDiagnosis {

    /// Records per student (student ID → skill ID → record).
    static func build(submissions: [Submission], exerciseSkills: [String: [String]]) -> [String: StudentSkills] {
        var result: [String: StudentSkills] = [:]
        for submission in submissions {
            guard let final = submission.finalResult else { continue }
            let skills = exerciseSkills[submission.exerciseID] ?? []
            func record(_ skillID: String, success: Bool, step: StepDiagnosis?) {
                var entry = result[submission.studentID, default: [:]][skillID] ?? SkillRecord(skillID: skillID)
                entry.add(SkillEvidence(
                    submissionID: submission.id,
                    exerciseID: submission.exerciseID,
                    date: submission.timestamp,
                    success: success,
                    attempt: submission.attemptNumber,
                    errorType: step?.errorType,
                    note: step?.note
                ))
                result[submission.studentID, default: [:]][skillID] = entry
            }
            if final.isSuccess {
                skills.forEach { record($0, success: true, step: nil) }
                continue
            }
            var failed: [String: StepDiagnosis] = [:]
            var order: [String] = []
            for case let step? in submission.correctionResult?.diagnosis ?? [] where !step.isConsequence {
                guard let skillID = step.skillID, Taxonomy.shared.skill(skillID) != nil else { continue }
                if failed[skillID] == nil { order.append(skillID) }
                failed[skillID] = failed[skillID] ?? step
            }
            if order.isEmpty {
                skills.forEach { record($0, success: false, step: nil) }
            } else {
                order.forEach { record($0, success: false, step: failed[$0]) }
            }
        }
        return result
    }

    /// Weak skills first (not mastered, then fragile), most failures first.
    static func weakSkills(_ skills: StudentSkills) -> [SkillRecord] {
        skills.values
            .filter { $0.mastery.isWeak }
            .sorted { ($0.mastery, -$0.failures, $0.skillID) < ($1.mastery, -$1.failures, $1.skillID) }
    }

    /// Skills with a failed copy but too few copies for a verdict.
    static func toWatch(_ skills: StudentSkills) -> [SkillRecord] {
        skills.values.filter { $0.mastery == .toConfirm && $0.failures > 0 }.sorted { $0.skillID < $1.skillID }
    }

    /// "En Développer, Zoé a des lacunes : produit de trois facteurs (0/3).
    /// Erreur type : « … »."
    static func sentence(firstName: String, record: SkillRecord) -> String {
        guard let skill = Taxonomy.shared.skill(record.skillID) else { return "" }
        let head = LocalizationManager.shared.format(
            record.mastery == .notMastered
                ? "En %@, %@ ne maîtrise pas : %@ (%@/%@ réussis)."
                : "En %@, %@ est fragile : %@ (%@/%@ réussis).",
            skill.competency.label, firstName, skill.node.label.lowercasedFirst,
            String(record.successes), String(record.total)
        )
        guard let note = record.mistakes.first(where: { $0.note != nil })?.note else { return head }
        return head + " " + LocalizationManager.shared.format("Erreur type : « %@ »", note)
    }

    // MARK: - Class and domain

    struct ClassSkill: Hashable {
        let skillID: String
        /// Students with evidence on this skill.
        let students: Int
        let successes: Int
        let total: Int
        /// Student IDs by mastery (weakest first).
        let notMastered: [String]
        let fragile: [String]
        /// Recent notes of the class's mistakes on this skill.
        let notes: [String]

        var rate: Double { total > 0 ? Double(successes) / Double(total) : 0 }
        var struggling: Int { notMastered.count + fragile.count }
    }

    static func classSkills(_ perStudent: [String: StudentSkills]) -> [ClassSkill] {
        var bySkill: [String: [(String, SkillRecord)]] = [:]
        for (studentID, skills) in perStudent {
            for (skillID, record) in skills {
                bySkill[skillID, default: []].append((studentID, record))
            }
        }
        return bySkill.map { skillID, entries in
            let notes = entries.flatMap { $0.1.mistakes }
                .sorted { $0.date > $1.date }
                .compactMap(\.note)
            return ClassSkill(
                skillID: skillID,
                students: entries.count,
                successes: entries.reduce(0) { $0 + $1.1.successes },
                total: entries.reduce(0) { $0 + $1.1.total },
                notMastered: entries.filter { $0.1.mastery == .notMastered }.map(\.0).sorted(),
                fragile: entries.filter { $0.1.mastery == .fragile }.map(\.0).sorted(),
                notes: Array(NSOrderedSet(array: notes).array.compactMap { $0 as? String }.prefix(5))
            )
        }
        .sorted { ($0.struggling, -$0.rate) > ($1.struggling, -$1.rate) }
    }

    /// Success rate of a student on a set of skills (competency, domain).
    static func rate(_ skills: StudentSkills, within skillIDs: Set<String>) -> (successes: Int, total: Int) {
        skills.values.filter { skillIDs.contains($0.skillID) }
            .reduce((0, 0)) { ($0.0 + $1.successes, $0.1 + $1.total) }
    }

    static func errorTypeLabel(_ type: String) -> String {
        switch type {
        case "sign_error": return "Erreur de signe".tr
        case "arithmetic": return "Erreur de calcul".tr
        case "algebra": return "Règle algébrique".tr
        case "method": return "Méthode".tr
        case "conceptual": return "Notion mal comprise".tr
        case "incomplete": return "Réponse incomplète".tr
        case "notation": return "Notation".tr
        case "misread": return "Énoncé mal lu".tr
        default: return type
        }
    }
}

private extension String {
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
