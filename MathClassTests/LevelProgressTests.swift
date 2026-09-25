import XCTest
@testable import MathClass

final class LevelProgressTests: XCTestCase {
    private let handler = AssignmentModeHandler.shared

    private func history(_ results: [SubmissionResult]) -> [Submission] {
        results.enumerated().map { index, result in
            Submission(
                id: "s\(index)",
                studentID: "stu",
                exerciseID: "ex\(index)",
                assignmentID: "asg",
                attemptNumber: 1,
                finalResult: result,
                timestamp: Date(timeIntervalSince1970: Double(index))
            )
        }
    }

    func testFirstSuccessCountsOnce() {
        let progress = handler.computeLevelProgress(existingSubmissions: [], newResult: .success1st, attemptNumber: 1)
        XCTAssertEqual(progress.consecutiveCorrect, 1)
        XCTAssertEqual(progress.currentLevel, 1)
        XCTAssertFalse(progress.didAdvance)
    }

    func testThirdSuccessInARowLevelsUp() {
        let progress = handler.computeLevelProgress(
            existingSubmissions: history([.success1st, .success1st]),
            newResult: .success1st, attemptNumber: 1
        )
        XCTAssertTrue(progress.didAdvance)
        XCTAssertEqual(progress.currentLevel, 2)
        XCTAssertEqual(progress.consecutiveCorrect, 0)
    }

    func testStreakRestartsAfterALevelUp() {
        // Three successes already gave level 2; the fourth starts a new streak.
        let progress = handler.computeLevelProgress(
            existingSubmissions: history([.success1st, .success1st, .success1st]),
            newResult: .success1st, attemptNumber: 1
        )
        XCTAssertFalse(progress.didAdvance)
        XCTAssertEqual(progress.currentLevel, 2)
        XCTAssertEqual(progress.consecutiveCorrect, 1)
    }

    func testFailureResetsStreak() {
        let progress = handler.computeLevelProgress(
            existingSubmissions: history([.success1st, .success1st]),
            newResult: .failed, attemptNumber: 1
        )
        XCTAssertEqual(progress.consecutiveCorrect, 0)
        XCTAssertFalse(progress.didAdvance)
    }
}
