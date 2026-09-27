//
//  StatisticsService.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation

/// Aggregation service for teacher statistics.
/// Computes per-student, per-exercise, and per-class statistics from Submission data.
final class StatisticsService {

    static let shared = StatisticsService()

    private init() {}

    // MARK: - Per-Student Statistics

    /// Statistics for a single student within a class.
    struct StudentStats {
        let studentID: String
        let totalAttempts: Int
        let successCount: Int
        let failCount: Int
        let averageTime: TimeInterval
        let successRate: Double
        /// Success rate broken down by competency ID.
        var competencyRates: [String: Double]
    }

    /// Compute stats for a single student.
    func getStudentStats(
        studentID: String,
        submissions: [Submission],
        exerciseCompetencyMap: [String: [String]]
    ) -> StudentStats {
        let studentSubmissions = submissions.filter { $0.studentID == studentID && $0.finalResult != nil }

        // Best result per exercise of each assignment (a second try does not
        // count twice; the same exercise given in two lessons counts twice).
        let bestByExercise = bestResultPerExercise(studentSubmissions)

        let totalAttempts = bestByExercise.count
        let successCount = bestByExercise.values.filter { $0.finalResult?.isSuccess == true }.count
        let failCount = bestByExercise.values.filter { $0.finalResult == .failed }.count
        let totalTime = studentSubmissions.reduce(0.0) { $0 + $1.timeSpent }
        let averageTime = totalAttempts > 0 ? totalTime / Double(totalAttempts) : 0
        let successRate = totalAttempts > 0 ? Double(successCount) / Double(totalAttempts) : 0

        // Per-competency rates
        var competencyCorrect: [String: Int] = [:]
        var competencyTotal: [String: Int] = [:]

        for submission in bestByExercise.values {
            let competencies = exerciseCompetencyMap[submission.exerciseID] ?? []
            for competency in competencies {
                competencyTotal[competency, default: 0] += 1
                if submission.finalResult?.isSuccess == true {
                    competencyCorrect[competency, default: 0] += 1
                }
            }
        }

        var competencyRates: [String: Double] = [:]
        for (comp, total) in competencyTotal {
            competencyRates[comp] = Double(competencyCorrect[comp, default: 0]) / Double(total)
        }

        return StudentStats(
            studentID: studentID,
            totalAttempts: totalAttempts,
            successCount: successCount,
            failCount: failCount,
            averageTime: averageTime,
            successRate: successRate,
            competencyRates: competencyRates
        )
    }

    // MARK: - Per-Exercise Statistics

    /// Statistics for a single exercise across all students.
    struct ExerciseStats {
        let exerciseID: String
        let totalSubmissions: Int
        let successRate: Double
        let averageTime: TimeInterval
        /// Grouped errors by step index: stepIndex → count of students who failed there.
        var stepErrorCounts: [Int: Int]
        /// The most common wrong LaTeX expression per step index.
        var commonErrors: [Int: [(expression: String, count: Int)]]
        /// Student IDs who failed at each step.
        var failedStudentsByStep: [Int: [String]]
    }

    /// Compute stats for a single exercise.
    func getExerciseStats(
        exerciseID: String,
        submissions: [Submission]
    ) -> ExerciseStats {
        let exerciseSubmissions = submissions.filter { $0.exerciseID == exerciseID && $0.finalResult != nil }

        // Best result per student and assignment
        let bestByStudent = bestResultPerStudent(exerciseSubmissions)

        let totalSubmissions = bestByStudent.count
        let successCount = bestByStudent.values.filter { $0.finalResult?.isSuccess == true }.count
        let successRate = totalSubmissions > 0 ? Double(successCount) / Double(totalSubmissions) : 0
        let totalTime = bestByStudent.values.reduce(0.0) { $0 + $1.timeSpent }
        let averageTime = totalSubmissions > 0 ? totalTime / Double(totalSubmissions) : 0

        // Step error analysis
        var stepErrorCounts: [Int: Int] = [:]
        var stepExpressions: [Int: [String: Int]] = [:]
        var failedStudentsByStep: [Int: [String]] = [:]

        for submission in bestByStudent.values {
            let studentID = submission.studentID
            guard let correction = submission.correctionResult else { continue }

            for (index, isCorrect) in correction.stepResults.enumerated() {
                if !isCorrect {
                    stepErrorCounts[index, default: 0] += 1
                    failedStudentsByStep[index, default: []].append(studentID)

                    // Track the wrong expression
                    if index < submission.latexSteps.count {
                        let expr = submission.latexSteps[index]
                        stepExpressions[index, default: [:]][expr, default: 0] += 1
                    }
                }
            }
        }

        // Sort common errors by frequency
        var commonErrors: [Int: [(expression: String, count: Int)]] = [:]
        for (step, expressions) in stepExpressions {
            commonErrors[step] = expressions
                .map { (expression: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count }
        }

        return ExerciseStats(
            exerciseID: exerciseID,
            totalSubmissions: totalSubmissions,
            successRate: successRate,
            averageTime: averageTime,
            stepErrorCounts: stepErrorCounts,
            commonErrors: commonErrors,
            failedStudentsByStep: failedStudentsByStep
        )
    }

    // MARK: - Per-Class Statistics

    /// Overall class statistics.
    struct ClassStats {
        let classID: String
        let totalStudents: Int
        let totalSubmissions: Int
        let overallSuccessRate: Double
        let averageTime: TimeInterval
        /// Competencies sorted by weakness (lowest success rate first).
        var weakestCompetencies: [(competencyID: String, successRate: Double)]
        /// Students with success rate below 40%.
        var studentsInDifficulty: [(studentID: String, successRate: Double)]
    }

    /// Compute class-level statistics.
    func getClassStats(
        classID: String,
        studentIDs: [String],
        submissions: [Submission],
        exerciseCompetencyMap: [String: [String]]
    ) -> ClassStats {
        let classSubmissions = submissions.filter { studentIDs.contains($0.studentID) && $0.finalResult != nil }

        // Per-student stats
        var allStudentStats: [StudentStats] = []
        for studentID in studentIDs {
            let stats = getStudentStats(
                studentID: studentID,
                submissions: classSubmissions,
                exerciseCompetencyMap: exerciseCompetencyMap
            )
            allStudentStats.append(stats)
        }

        // Overall
        let totalSubmissions = allStudentStats.reduce(0) { $0 + $1.totalAttempts }
        let totalSuccess = allStudentStats.reduce(0) { $0 + $1.successCount }
        let overallSuccessRate = totalSubmissions > 0 ? Double(totalSuccess) / Double(totalSubmissions) : 0

        let totalTime = allStudentStats.reduce(0.0) { $0 + $1.averageTime * Double($1.totalAttempts) }
        let averageTime = totalSubmissions > 0 ? totalTime / Double(totalSubmissions) : 0

        // Weakest competencies — aggregate from the best (student, exercise)
        // submission pairs so multiple attempts on the same exercise don't
        // double-count. ISSUE-017 removed an earlier shadowed pass that
        // built per-student rates and threw them away here.
        var compCorrect: [String: Int] = [:]
        var compTotal: [String: Int] = [:]

        let bestPerStudentExercise = bestResultsGrouped(classSubmissions)
        for submission in bestPerStudentExercise {
            let competencies = exerciseCompetencyMap[submission.exerciseID] ?? []
            for comp in competencies {
                compTotal[comp, default: 0] += 1
                if submission.finalResult?.isSuccess == true {
                    compCorrect[comp, default: 0] += 1
                }
            }
        }

        let weakestCompetencies = compTotal
            .map { comp, total in
                (competencyID: comp, successRate: total > 0 ? Double(compCorrect[comp, default: 0]) / Double(total) : 0.0)
            }
            .sorted { $0.successRate < $1.successRate }

        // Students in difficulty (< 40% success rate)
        let studentsInDifficulty = allStudentStats
            .filter { $0.totalAttempts > 0 && $0.successRate < 0.4 }
            .map { (studentID: $0.studentID, successRate: $0.successRate) }
            .sorted { $0.successRate < $1.successRate }

        return ClassStats(
            classID: classID,
            totalStudents: studentIDs.count,
            totalSubmissions: totalSubmissions,
            overallSuccessRate: overallSuccessRate,
            averageTime: averageTime,
            weakestCompetencies: weakestCompetencies,
            studentsInDifficulty: studentsInDifficulty
        )
    }

    // MARK: - Helpers

    /// Best submission per key: success over failure, then 1st try over 2nd.
    private func best(_ submissions: [Submission], by key: (Submission) -> String) -> [String: Submission] {
        var best: [String: Submission] = [:]
        for submission in submissions {
            let k = key(submission)
            if let existing = best[k] {
                if (submission.finalResult?.isSuccess == true && existing.finalResult?.isSuccess != true)
                    || (submission.finalResult == .success1st && existing.finalResult != .success1st) {
                    best[k] = submission
                }
            } else {
                best[k] = submission
            }
        }
        return best
    }

    /// Best result per exercise of each assignment (one student's copies).
    /// Keyed by assignment too: an exercise reused in another lesson is
    /// another piece of work, not a retry.
    private func bestResultPerExercise(_ submissions: [Submission]) -> [String: Submission] {
        best(submissions) { "\($0.assignmentID)|\($0.exerciseID)" }
    }

    /// Best result per student and assignment (one exercise's copies).
    private func bestResultPerStudent(_ submissions: [Submission]) -> [String: Submission] {
        best(submissions) { "\($0.studentID)|\($0.assignmentID)" }
    }

    /// Best result per (student, assignment, exercise) — flattened list.
    private func bestResultsGrouped(_ submissions: [Submission]) -> [Submission] {
        Array(best(submissions) { "\($0.studentID)|\($0.assignmentID)|\($0.exerciseID)" }.values)
    }

    // MARK: - Slice 8: error-pattern co-occurrence (X→Y)

    /// One edge of an error-pattern co-occurrence graph: students who made
    /// error category `from` also tended to make error category `to`.
    struct ErrorCoOccurrence: Hashable {
        let from: String
        let to: String
        /// Number of students who exhibited both errors.
        let studentCount: Int
        /// Conditional probability: P(to | from) across the cohort.
        let conditional: Double
    }

    /// Compute pairwise error-category co-occurrence across a class. Uses
    /// `CorrectionResult.errorTags` populated by the Cloud Function. An
    /// edge `from → to` is emitted when `from != to` and both appear in
    /// the same student's history with `studentCount >= 2`. Sorted by
    /// `conditional` descending.
    func errorCoOccurrence(
        submissions: [Submission],
        minCount: Int = 2
    ) -> [ErrorCoOccurrence] {
        // Build per-student set of unique error categories.
        var perStudent: [String: Set<String>] = [:]
        for sub in submissions {
            let tags = sub.correctionResult?.errorTags ?? []
            let valid = Set(tags.compactMap { $0?.lowercased() }).filter { !$0.isEmpty }
            if valid.isEmpty { continue }
            perStudent[sub.studentID, default: []].formUnion(valid)
        }

        // Pair counts and per-tag frequency.
        var pairCounts: [String: Int] = [:]      // "from|to" → students with both
        var fromCounts: [String: Int] = [:]      // "from" → students with this tag
        for tags in perStudent.values {
            let arr = Array(tags)
            for tag in arr {
                fromCounts[tag, default: 0] += 1
            }
            for i in 0..<arr.count {
                for j in 0..<arr.count where i != j {
                    pairCounts["\(arr[i])|\(arr[j])", default: 0] += 1
                }
            }
        }

        var edges: [ErrorCoOccurrence] = []
        for (key, count) in pairCounts where count >= minCount {
            let parts = key.split(separator: "|", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let from = String(parts[0])
            let to = String(parts[1])
            let denom = fromCounts[from, default: 0]
            let conditional = denom > 0 ? Double(count) / Double(denom) : 0
            edges.append(.init(from: from, to: to, studentCount: count, conditional: conditional))
        }
        return edges.sorted { $0.conditional > $1.conditional }
    }

    // MARK: - Slice 8: per-concept progress over time

    /// One bucket of a per-concept time-series.
    struct ConceptTrendPoint: Hashable {
        let weekStart: Date
        let competencyID: String
        let successRate: Double
        let totalAttempts: Int
    }

    /// Aggregate success rate per `competencyID` per week (Monday-anchored)
    /// over the last `weeks` weeks. Useful for the per-student trend
    /// chart and the class-average evolution chart.
    func conceptTrend(
        submissions: [Submission],
        exerciseCompetencyMap: [String: [String]],
        weeks: Int = 12,
        now: Date = Date()
    ) -> [ConceptTrendPoint] {
        let calendar = Calendar(identifier: .iso8601)
        let cutoff = calendar.date(byAdding: .weekOfYear, value: -weeks, to: now) ?? now
        struct Bucket { var ok = 0; var total = 0 }
        var buckets: [String: Bucket] = [:]  // "yyyy-MM-dd|competency" → bucket

        for sub in submissions where sub.timestamp >= cutoff {
            let comps = exerciseCompetencyMap[sub.exerciseID] ?? []
            guard !comps.isEmpty, let final = sub.finalResult else { continue }
            // Snap timestamp to the start of its ISO week.
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: sub.timestamp)
            components.weekday = calendar.firstWeekday
            guard let weekStart = calendar.date(from: components) else { continue }
            let weekKey = ISO8601DateFormatter().string(from: weekStart)
            for comp in comps {
                var b = buckets["\(weekKey)|\(comp)"] ?? Bucket()
                b.total += 1
                if final.isSuccess { b.ok += 1 }
                buckets["\(weekKey)|\(comp)"] = b
            }
        }

        var points: [ConceptTrendPoint] = []
        for (key, b) in buckets {
            let parts = key.split(separator: "|", maxSplits: 1)
            guard parts.count == 2 else { continue }
            guard let weekStart = ISO8601DateFormatter().date(from: String(parts[0])) else { continue }
            let comp = String(parts[1])
            let rate = b.total > 0 ? Double(b.ok) / Double(b.total) : 0
            points.append(.init(weekStart: weekStart, competencyID: comp, successRate: rate, totalAttempts: b.total))
        }
        return points.sorted { $0.weekStart < $1.weekStart }
    }

    // MARK: - Slice 8: error-tag rollup

    /// Per-category count of error tags across the class. Powers the
    /// AI-derived error-taxonomy view.
    func errorTagBreakdown(submissions: [Submission]) -> [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for sub in submissions {
            let tags = sub.correctionResult?.errorTags ?? []
            for raw in tags {
                guard let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { continue }
                counts[t, default: 0] += 1
            }
        }
        return counts.map { (tag: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }
}
