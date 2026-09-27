//
//  LiveProgress.swift
//  MathClass
//
//  Where each student stands in the lesson's assignment, for the teacher's
//  live view: how many exercises are done, whether the last copy needs
//  fixing, whether the student has gone quiet.
//

import Foundation

struct LiveProgress: Equatable {

    enum State: Equatable {
        case notStarted
        case working
        /// The last copy was wrong and a second try is expected.
        case needsFix
        /// No copy for a while (minutes).
        case idle(minutes: Int)
        case finished
    }

    let state: State
    /// Exercises of the assignment given to this student.
    let assigned: Int
    /// Exercises settled: right, or wrong with no try left.
    let done: Int
    let succeeded: Int
    /// Exercise of the latest copy.
    let currentExerciseID: String?

    /// A student without a copy for this long is shown as idle.
    static let idleAfter: TimeInterval = 5 * 60

    /// - Parameters:
    ///   - submissions: this student's copies for the assignment.
    ///   - assignedExerciseIDs: the exercises of the assignment given to them.
    ///   - allowsRetry: whether a wrong first try can be redone.
    static func compute(
        submissions: [Submission],
        assignedExerciseIDs: [String],
        allowsRetry: Bool,
        now: Date
    ) -> LiveProgress {
        let assigned = Set(assignedExerciseIDs)
        guard let latest = submissions.max(by: { $0.timestamp < $1.timestamp }) else {
            return LiveProgress(state: .notStarted, assigned: assigned.count, done: 0, succeeded: 0, currentExerciseID: nil)
        }

        var settled: Set<String> = []
        var succeeded: Set<String> = []
        for submission in submissions where assigned.contains(submission.exerciseID) {
            switch submission.finalResult {
            case .success1st, .success2nd:
                settled.insert(submission.exerciseID)
                succeeded.insert(submission.exerciseID)
            case .failed:
                if !allowsRetry || submission.attemptNumber >= 2 {
                    settled.insert(submission.exerciseID)
                }
            case .none:
                break
            }
        }

        let state: State
        if !assigned.isEmpty && settled.count >= assigned.count {
            state = .finished
        } else if allowsRetry, latest.finalResult == .failed, latest.attemptNumber < 2 {
            state = .needsFix
        } else if now.timeIntervalSince(latest.timestamp) > idleAfter {
            state = .idle(minutes: Int(now.timeIntervalSince(latest.timestamp) / 60))
        } else {
            state = .working
        }
        return LiveProgress(
            state: state,
            assigned: assigned.count,
            done: settled.count,
            succeeded: succeeded.count,
            currentExerciseID: latest.exerciseID
        )
    }
}

extension AssignmentExercise {
    /// Whether this exercise is given to the student: untargeted, or
    /// targeted at them or at their group.
    func isAssigned(to studentID: String, groupIDs: Set<String>) -> Bool {
        let hasStudentTarget = !(targetStudentIDs?.isEmpty ?? true)
        let hasGroupTarget = (targetGroupID?.isEmpty == false)
        if !hasStudentTarget && !hasGroupTarget { return true }
        if let ids = targetStudentIDs, ids.contains(studentID) { return true }
        if let groupID = targetGroupID, groupIDs.contains(groupID) { return true }
        return false
    }
}

// MARK: - Teacher live view

extension TeacherViewModel {
    /// The assignment a class is working on: the one of the latest copy of
    /// one of its students, else its newest active assignment.
    func lessonAssignment(classID: String, studentIDs: Set<String>) -> Assignment? {
        let active = assignmentRepo.teacherAssignments.filter { $0.classID == classID && $0.isActive }
        if let latest = submissionRepo.submissions
            .filter({ studentIDs.contains($0.studentID) })
            .max(by: { $0.timestamp < $1.timestamp }),
           let assignment = active.first(where: { $0.id == latest.assignmentID }) {
            return assignment
        }
        return active.max(by: { $0.createdAt < $1.createdAt })
    }

    /// Where the student stands in the assignment.
    func liveProgress(of student: Student, in assignment: Assignment, now: Date) -> LiveProgress? {
        guard let studentID = student.id, let assignmentID = assignment.id else { return nil }
        let groupIDs: Set<String> = student.groupID.map { [$0] } ?? []
        let exerciseIDs = (assignmentRepo.assignmentExercises[assignmentID] ?? [])
            .filter { $0.isAssigned(to: studentID, groupIDs: groupIDs) }
            .map(\.exerciseID)
        let copies = submissionRepo.submissions
            .filter { $0.studentID == studentID && $0.assignmentID == assignmentID }
        return LiveProgress.compute(
            submissions: copies,
            assignedExerciseIDs: exerciseIDs,
            allowsRetry: assignment.mode.allows2ndChance,
            now: now
        )
    }
}

extension Array where Element == LiveProgress? {
    /// Head count per state for the class summary line.
    var liveCounts: (working: Int, finished: Int, needsFix: Int, idle: Int, notStarted: Int) {
        let states = compactMap { $0?.state }
        let finished = states.filter { $0 == .finished }.count
        let needsFix = states.filter { $0 == .needsFix }.count
        let idle = states.filter { if case .idle = $0 { return true } else { return false } }.count
        let notStarted = states.filter { $0 == .notStarted }.count
        return (states.count - finished - needsFix - idle - notStarted, finished, needsFix, idle, notStarted)
    }
}
