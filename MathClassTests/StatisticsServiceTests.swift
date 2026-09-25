//
//  StatisticsServiceTests.swift
//  MathClassTests
//
//  Pure-logic tests for StatisticsService. The service holds no state,
//  takes plain `[Submission]` arrays in, and returns aggregation structs.
//  No Firebase, no SwiftUI — runs in milliseconds.
//
//  Covers the slice-8 aggregations (errorTagBreakdown, errorCoOccurrence,
//  conceptTrend) plus the per-student / per-exercise / per-class rollups
//  that power the macOS Statistics view.
//

import XCTest
@testable import MathClass

final class StatisticsServiceTests: XCTestCase {

    private let service = StatisticsService.shared

    // MARK: - Fixtures

    private func makeSubmission(
        student: String,
        exercise: String,
        result: SubmissionResult?,
        attempt: Int = 1,
        stepResults: [Bool] = [],
        errorTags: [String?]? = nil,
        timeSpent: TimeInterval = 60,
        daysAgo: Int = 0
    ) -> Submission {
        let correction: CorrectionResult? = stepResults.isEmpty && errorTags == nil
            ? nil
            : CorrectionResult(
                stepResults: stepResults,
                firstErrorIndex: stepResults.firstIndex(of: false),
                notationNoteKey: nil,
                errorTags: errorTags
            )
        let timestamp = Calendar(identifier: .iso8601)
            .date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return Submission(
            studentID: student,
            exerciseID: exercise,
            assignmentID: "assign1",
            attemptNumber: attempt,
            latexSteps: stepResults.map { _ in "x" },
            correctionResult: correction,
            finalResult: result,
            timeSpent: timeSpent,
            timestamp: timestamp
        )
    }

    // MARK: - getStudentStats

    func testStudentStatsCountsBestPerExercise() {
        // 2nd attempt on ex1 succeeds → counts as success, not as 2 attempts.
        let subs = [
            makeSubmission(student: "s1", exercise: "ex1", result: .failed, attempt: 1),
            makeSubmission(student: "s1", exercise: "ex1", result: .success2nd, attempt: 2),
            makeSubmission(student: "s1", exercise: "ex2", result: .success1st),
            // Different student — must be filtered out.
            makeSubmission(student: "s2", exercise: "ex1", result: .failed),
        ]
        let stats = service.getStudentStats(
            studentID: "s1",
            submissions: subs,
            exerciseCompetencyMap: [:]
        )
        XCTAssertEqual(stats.totalAttempts, 2)  // ex1 + ex2
        XCTAssertEqual(stats.successCount, 2)
        XCTAssertEqual(stats.failCount, 0)
        XCTAssertEqual(stats.successRate, 1.0, accuracy: 0.001)
    }

    func testStudentStatsCompetencyRates() {
        let subs = [
            makeSubmission(student: "s1", exercise: "ex1", result: .success1st),
            makeSubmission(student: "s1", exercise: "ex2", result: .failed),
        ]
        let map = ["ex1": ["alg"], "ex2": ["alg", "geom"]]
        let stats = service.getStudentStats(
            studentID: "s1",
            submissions: subs,
            exerciseCompetencyMap: map
        )
        // alg: 1 success / 2 total = 0.5; geom: 0/1 = 0
        XCTAssertEqual(stats.competencyRates["alg"] ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(stats.competencyRates["geom"] ?? -1, 0.0, accuracy: 0.001)
    }

    func testStudentStatsEmptyInput() {
        let stats = service.getStudentStats(
            studentID: "s1",
            submissions: [],
            exerciseCompetencyMap: [:]
        )
        XCTAssertEqual(stats.totalAttempts, 0)
        XCTAssertEqual(stats.successRate, 0)
        XCTAssertEqual(stats.averageTime, 0)
    }

    // MARK: - getExerciseStats

    func testExerciseStatsStepErrorCounts() {
        // Two students fail at step 1 (the second step); one student fully
        // succeeds. firstErrorIndex bookkeeping should land in stepErrorCounts.
        let subs = [
            makeSubmission(student: "s1", exercise: "ex1", result: .failed,
                           stepResults: [true, false, false]),
            makeSubmission(student: "s2", exercise: "ex1", result: .failed,
                           stepResults: [true, false, true]),
            makeSubmission(student: "s3", exercise: "ex1", result: .success1st,
                           stepResults: [true, true, true]),
        ]
        let stats = service.getExerciseStats(exerciseID: "ex1", submissions: subs)
        XCTAssertEqual(stats.totalSubmissions, 3)
        XCTAssertEqual(stats.successRate, 1.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(stats.stepErrorCounts[1], 2)
        XCTAssertEqual(stats.stepErrorCounts[2], 1)
        XCTAssertNil(stats.stepErrorCounts[0])
        XCTAssertEqual(stats.failedStudentsByStep[1]?.sorted(), ["s1", "s2"])
    }

    func testExerciseStatsCommonErrorsSortedByFrequency() {
        // Both s1 and s2 wrote "x=5" at step 1; s3 wrote "x=6".
        let mk: (String, String) -> Submission = { sid, expr in
            var s = self.makeSubmission(
                student: sid, exercise: "ex1", result: .failed,
                stepResults: [true, false])
            s.latexSteps = ["x", expr]
            return s
        }
        let subs = [mk("s1", "x=5"), mk("s2", "x=5"), mk("s3", "x=6")]
        let stats = service.getExerciseStats(exerciseID: "ex1", submissions: subs)
        let step1 = stats.commonErrors[1] ?? []
        XCTAssertEqual(step1.first?.expression, "x=5")
        XCTAssertEqual(step1.first?.count, 2)
    }

    // MARK: - getClassStats

    func testClassStatsWeakestCompetenciesAndDifficulty() {
        // 3 students. s1 succeeds on both; s2 fails alg; s3 fails alg and geom.
        let subs = [
            makeSubmission(student: "s1", exercise: "ex1", result: .success1st),
            makeSubmission(student: "s1", exercise: "ex2", result: .success1st),
            makeSubmission(student: "s2", exercise: "ex1", result: .failed),
            makeSubmission(student: "s2", exercise: "ex2", result: .success1st),
            makeSubmission(student: "s3", exercise: "ex1", result: .failed),
            makeSubmission(student: "s3", exercise: "ex2", result: .failed),
        ]
        let map = ["ex1": ["alg"], "ex2": ["geom"]]
        let cls = service.getClassStats(
            classID: "c1",
            studentIDs: ["s1", "s2", "s3"],
            submissions: subs,
            exerciseCompetencyMap: map
        )
        // alg: 1 success / 3 attempts = 0.333; geom: 2 / 3 = 0.666
        // weakest comes first (lowest rate first).
        XCTAssertEqual(cls.weakestCompetencies.first?.competencyID, "alg")
        XCTAssertEqual(cls.weakestCompetencies.last?.competencyID, "geom")
        // s3 is the only student < 40 % (0/2 = 0); s2 is at 50 % so excluded.
        XCTAssertEqual(cls.studentsInDifficulty.map(\.studentID), ["s3"])
    }

    // MARK: - errorTagBreakdown

    func testErrorTagBreakdownAggregatesAndSorts() {
        let subs = [
            makeSubmission(student: "s1", exercise: "ex1", result: .failed,
                           errorTags: ["sign_error", "arithmetic"]),
            makeSubmission(student: "s2", exercise: "ex1", result: .failed,
                           errorTags: ["sign_error", nil, "  "]),
            makeSubmission(student: "s3", exercise: "ex2", result: .failed,
                           errorTags: ["notation"]),
        ]
        let breakdown = service.errorTagBreakdown(submissions: subs)
        // Sorted by count desc: sign_error=2, arithmetic=1, notation=1.
        XCTAssertEqual(breakdown.first?.tag, "sign_error")
        XCTAssertEqual(breakdown.first?.count, 2)
        let tags = breakdown.map(\.tag)
        XCTAssertTrue(tags.contains("arithmetic"))
        XCTAssertTrue(tags.contains("notation"))
        // Nil and blank tags must not leak in.
        XCTAssertFalse(tags.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }))
    }

    func testErrorTagBreakdownEmpty() {
        XCTAssertEqual(service.errorTagBreakdown(submissions: []).count, 0)
    }

    // MARK: - errorCoOccurrence

    func testErrorCoOccurrenceRespectsMinCount() {
        // Two students both have sign_error AND arithmetic. One student has
        // only notation. Pair (sign_error, arithmetic) → count 2; should
        // pass the default minCount of 2. notation pairs only appear once
        // and are filtered.
        let subs = [
            makeSubmission(student: "s1", exercise: "ex1", result: .failed,
                           errorTags: ["sign_error", "arithmetic"]),
            makeSubmission(student: "s2", exercise: "ex2", result: .failed,
                           errorTags: ["sign_error", "arithmetic"]),
            makeSubmission(student: "s3", exercise: "ex3", result: .failed,
                           errorTags: ["notation", "sign_error"]),
        ]
        let edges = service.errorCoOccurrence(submissions: subs)
        XCTAssertTrue(edges.contains { $0.from == "sign_error" && $0.to == "arithmetic" })
        XCTAssertTrue(edges.contains { $0.from == "arithmetic" && $0.to == "sign_error" })
        // notation→anything occurs only once → filtered by minCount=2.
        XCTAssertFalse(edges.contains { $0.from == "notation" })
    }

    func testErrorCoOccurrenceConditionalProbability() {
        // 3 students all have "alg"; 2 of them also have "geom".
        // P(geom | alg) should be 2/3.
        let subs = [
            makeSubmission(student: "s1", exercise: "e", result: .failed,
                           errorTags: ["alg", "geom"]),
            makeSubmission(student: "s2", exercise: "e", result: .failed,
                           errorTags: ["alg", "geom"]),
            makeSubmission(student: "s3", exercise: "e", result: .failed,
                           errorTags: ["alg"]),
        ]
        let edges = service.errorCoOccurrence(submissions: subs)
        let algToGeom = edges.first { $0.from == "alg" && $0.to == "geom" }
        XCTAssertNotNil(algToGeom)
        XCTAssertEqual(algToGeom?.conditional ?? -1, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(algToGeom?.studentCount, 2)
    }

    // MARK: - conceptTrend

    func testConceptTrendBucketsByWeek() {
        // Two submissions this week, one 2 weeks ago. Should produce at
        // least 2 distinct buckets when both have competencies.
        let subs = [
            makeSubmission(student: "s1", exercise: "ex1", result: .success1st, daysAgo: 0),
            makeSubmission(student: "s2", exercise: "ex1", result: .failed, daysAgo: 2),
            makeSubmission(student: "s3", exercise: "ex1", result: .success1st, daysAgo: 15),
        ]
        let map = ["ex1": ["alg"]]
        let points = service.conceptTrend(
            submissions: subs,
            exerciseCompetencyMap: map,
            weeks: 12
        )
        XCTAssertGreaterThanOrEqual(points.count, 2)
        // All points should be for the alg competency.
        XCTAssertTrue(points.allSatisfy { $0.competencyID == "alg" })
        // Sorted ascending by weekStart.
        XCTAssertEqual(points, points.sorted { $0.weekStart < $1.weekStart })
    }

    func testConceptTrendExcludesOutsideWindow() {
        // 100 days ago is far outside the 4-week window.
        let subs = [
            makeSubmission(student: "s1", exercise: "ex1", result: .success1st, daysAgo: 100),
        ]
        let map = ["ex1": ["alg"]]
        let points = service.conceptTrend(
            submissions: subs,
            exerciseCompetencyMap: map,
            weeks: 4
        )
        XCTAssertEqual(points.count, 0)
    }

    func testConceptTrendIgnoresSubmissionsWithoutFinalResult() {
        let subs = [
            makeSubmission(student: "s1", exercise: "ex1", result: nil, daysAgo: 1),
        ]
        let map = ["ex1": ["alg"]]
        XCTAssertEqual(
            service.conceptTrend(submissions: subs, exerciseCompetencyMap: map).count,
            0
        )
    }
}
