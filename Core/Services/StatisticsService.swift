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
        let studentSubmissions = submissions.filter { $0.studentID == studentID }

        // Use best result per exercise (avoid double-counting attempts)
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

        for (exerciseID, submission) in bestByExercise {
            let competencies = exerciseCompetencyMap[exerciseID] ?? []
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
        let exerciseSubmissions = submissions.filter { $0.exerciseID == exerciseID }

        // Best result per student
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

        for (studentID, submission) in bestByStudent {
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
        let classSubmissions = submissions.filter { studentIDs.contains($0.studentID) }

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

        // Weakest competencies (aggregate across all students)
        var competencyCorrect: [String: Int] = [:]
        var competencyTotal: [String: Int] = [:]

        for stats in allStudentStats {
            for (comp, rate) in stats.competencyRates {
                // Reconstruct from rate + totals
                let studentCompTotal = stats.totalAttempts > 0 ? 1 : 0
                competencyTotal[comp, default: 0] += studentCompTotal
                if rate >= 0.5 {
                    competencyCorrect[comp, default: 0] += 1
                }
            }
        }

        // Recalculate properly from raw submissions
        var compCorrectRaw: [String: Int] = [:]
        var compTotalRaw: [String: Int] = [:]

        let bestPerStudentExercise = bestResultsGrouped(classSubmissions)
        for submission in bestPerStudentExercise {
            let competencies = exerciseCompetencyMap[submission.exerciseID] ?? []
            for comp in competencies {
                compTotalRaw[comp, default: 0] += 1
                if submission.finalResult?.isSuccess == true {
                    compCorrectRaw[comp, default: 0] += 1
                }
            }
        }

        let weakestCompetencies = compTotalRaw
            .map { comp, total in
                (competencyID: comp, successRate: total > 0 ? Double(compCorrectRaw[comp, default: 0]) / Double(total) : 0.0)
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

    /// Best submission result per exercise (for a single student's submissions).
    private func bestResultPerExercise(_ submissions: [Submission]) -> [String: Submission] {
        var best: [String: Submission] = [:]

        for submission in submissions {
            let exerciseID = submission.exerciseID
            if let existing = best[exerciseID] {
                // Prefer success over failure, then 1st > 2nd > failed
                if (submission.finalResult?.isSuccess == true && existing.finalResult?.isSuccess != true)
                    || (submission.finalResult == .success1st && existing.finalResult != .success1st) {
                    best[exerciseID] = submission
                }
            } else {
                best[exerciseID] = submission
            }
        }

        return best
    }

    /// Best submission result per student (for a single exercise's submissions).
    private func bestResultPerStudent(_ submissions: [Submission]) -> [String: Submission] {
        var best: [String: Submission] = [:]

        for submission in submissions {
            let studentID = submission.studentID
            if let existing = best[studentID] {
                if (submission.finalResult?.isSuccess == true && existing.finalResult?.isSuccess != true)
                    || (submission.finalResult == .success1st && existing.finalResult != .success1st) {
                    best[studentID] = submission
                }
            } else {
                best[studentID] = submission
            }
        }

        return best
    }

    /// Get the best result per (student, exercise) pair — flattened list.
    private func bestResultsGrouped(_ submissions: [Submission]) -> [Submission] {
        var best: [String: Submission] = [:]

        for submission in submissions {
            let key = "\(submission.studentID)_\(submission.exerciseID)"
            if let existing = best[key] {
                if (submission.finalResult?.isSuccess == true && existing.finalResult?.isSuccess != true) {
                    best[key] = submission
                }
            } else {
                best[key] = submission
            }
        }

        return Array(best.values)
    }
}
