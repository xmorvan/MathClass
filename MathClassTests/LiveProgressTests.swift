//
//  LiveProgressTests.swift
//  MathClassTests
//
//  Where a student stands in the lesson, as the teacher's live view
//  shows it.
//

import XCTest
@testable import MathClass

final class LiveProgressTests: XCTestCase {

    private let now = Date()
    private let exercises = ["e1", "e2", "e3"]

    private func copy(_ exercise: String, _ result: SubmissionResult?, attempt: Int = 1, minutesAgo: Double = 1) -> Submission {
        Submission(studentID: "s", exerciseID: exercise, assignmentID: "a", attemptNumber: attempt,
                   finalResult: result, timestamp: now.addingTimeInterval(-minutesAgo * 60))
    }

    private func progress(_ copies: [Submission], allowsRetry: Bool = true) -> LiveProgress {
        LiveProgress.compute(submissions: copies, assignedExerciseIDs: exercises, allowsRetry: allowsRetry, now: now)
    }

    func testNoCopyIsNotStarted() {
        XCTAssertEqual(progress([]).state, .notStarted)
        XCTAssertEqual(progress([]).assigned, 3)
    }

    func testWrongFirstTryNeedsFixing() {
        let p = progress([copy("e1", .success1st, minutesAgo: 3), copy("e2", .failed)])
        XCTAssertEqual(p.state, .needsFix)
        XCTAssertEqual(p.done, 1)
        XCTAssertEqual(p.currentExerciseID, "e2")
    }

    func testNeedsFixNamesTheFailedSkill() {
        var wrong = copy("e2", .failed)
        wrong.correctionResult = CorrectionResult(stepResults: [false, false], diagnosis: [
            StepDiagnosis(skillID: "nombres.puissances.produit-meme-base", errorType: "algebra"),
            StepDiagnosis(skillID: nil, errorType: "consequence"),
        ])
        XCTAssertEqual(progress([wrong]).mistakeSkillID, "nombres.puissances.produit-meme-base")
    }

    func testWrongSecondTrySettlesTheExercise() {
        let p = progress([copy("e1", .failed, minutesAgo: 2), copy("e1", .failed, attempt: 2)])
        XCTAssertEqual(p.state, .working)
        XCTAssertEqual(p.done, 1)
        XCTAssertEqual(p.succeeded, 0)
    }

    func testWithoutRetryAWrongCopyIsFinal() {
        let p = progress([copy("e1", .failed)], allowsRetry: false)
        XCTAssertEqual(p.state, .working)
        XCTAssertEqual(p.done, 1)
    }

    func testAllSettledIsFinished() {
        let p = progress([copy("e1", .success1st), copy("e2", .success2nd), copy("e3", .failed, attempt: 2)])
        XCTAssertEqual(p.state, .finished)
        XCTAssertEqual(p.succeeded, 2)
    }

    func testQuietStudentIsIdle() {
        XCTAssertEqual(progress([copy("e1", .success1st, minutesAgo: 8)]).state, .idle(minutes: 8))
    }

    func testTargetedExercises() {
        let forAll = AssignmentExercise(assignmentID: "a", exerciseID: "e1", order: 1)
        var forLea = AssignmentExercise(assignmentID: "a", exerciseID: "e2", order: 2)
        forLea.targetStudentIDs = ["lea"]
        var forGroup = AssignmentExercise(assignmentID: "a", exerciseID: "e3", order: 3)
        forGroup.targetGroupID = "g1"
        XCTAssertTrue(forAll.isAssigned(to: "noe", groupIDs: []))
        XCTAssertFalse(forLea.isAssigned(to: "noe", groupIDs: []))
        XCTAssertTrue(forLea.isAssigned(to: "lea", groupIDs: []))
        XCTAssertTrue(forGroup.isAssigned(to: "noe", groupIDs: ["g1"]))
    }
}
