//
//  TeacherViewModel.swift
//  MathClass
//
//  Created by Xavier Morvan on 18.11.2024.
//

import Foundation
import Combine
// Per CLAUDE.md, ViewModels must not import SwiftUI. FirebaseStorage is
// owned by DataService (we delegate to `uploadExerciseImage` →
// `DataService.uploadData`). FirebaseFirestore was unused.

/// ViewModel for the teacher dashboard.
/// Manages UI state and delegates all data operations to repositories.
/// Not a singleton — created as @StateObject at the teacher dashboard scope.
@MainActor
class TeacherViewModel: ObservableObject {

    // MARK: - Repositories (injected)

    let classRepo: ClassRepository
    let studentRepo: StudentRepository
    let exerciseRepo: ExerciseRepository
    let chapterRepo: ChapterRepository
    let assignmentRepo: AssignmentRepository
    let submissionRepo: SubmissionRepository
    let groupRepo: GroupRepository
    let periodRepo: PeriodRepository
    let sessionRepo: SessionRepository

    // MARK: - UI State

    @Published var showAddStudent: Bool = false
    @Published var showAddExercise: Bool = false
    @Published var showCreateAssignment: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    /// Currently selected class for detail views
    @Published var selectedClassID: String?

    // MARK: - Combine

    private var cancellables: Set<AnyCancellable> = []

    /// Relays each repository's changes to this view model. Kept apart from
    /// `cancellables`, which `stopListening()` clears.
    private var repositoryForwarding: Set<AnyCancellable> = []

    // MARK: - Computed Convenience

    var classes: [ClassRoom] { classRepo.classes }
    var students: [Student] { studentRepo.students }
    var exercises: [Exercise] { exerciseRepo.exercises }
    var chapters: [Chapter] { chapterRepo.chapters }
    var assignments: [Assignment] { assignmentRepo.assignments }

    /// Submissions across all the teacher's classes (powers the inbox).
    var recentSubmissions: [Submission] { submissionRepo.submissions }

    /// Best-effort cross-class student directory used by the submission inbox
    /// to display student names. Refreshed when the class list changes.
    @Published private(set) var studentDirectory: [String: Student] = [:]

    /// Students filtered by a class ID
    func studentsInClass(_ classID: String) -> [Student] {
        studentRepo.students.filter { $0.classID == classID }
    }

    // MARK: - Initialization

    init(
        classRepo: ClassRepository? = nil,
        studentRepo: StudentRepository? = nil,
        exerciseRepo: ExerciseRepository? = nil,
        chapterRepo: ChapterRepository? = nil,
        assignmentRepo: AssignmentRepository? = nil,
        submissionRepo: SubmissionRepository? = nil,
        groupRepo: GroupRepository? = nil,
        periodRepo: PeriodRepository? = nil,
        sessionRepo: SessionRepository? = nil
    ) {
        let dataService = DataService.shared
        self.classRepo = classRepo ?? dataService.classRepository
        self.studentRepo = studentRepo ?? dataService.studentRepository
        self.exerciseRepo = exerciseRepo ?? dataService.exerciseRepository
        self.chapterRepo = chapterRepo ?? dataService.chapterRepository
        self.assignmentRepo = assignmentRepo ?? dataService.assignmentRepository
        self.submissionRepo = submissionRepo ?? dataService.submissionRepository
        self.groupRepo = groupRepo ?? dataService.groupRepository
        self.periodRepo = periodRepo ?? dataService.periodRepository
        self.sessionRepo = sessionRepo ?? dataService.sessionRepository
        forwardRepositoryChanges()
    }

    /// Views read repository data through computed properties
    /// (`classes`, `studentsInClass`, …), so they only re-render when this
    /// object publishes. Without this relay, data arriving from Firestore
    /// listeners stayed invisible until some unrelated state changed.
    private func forwardRepositoryChanges() {
        let publishers: [ObservableObjectPublisher] = [
            classRepo.objectWillChange,
            studentRepo.objectWillChange,
            exerciseRepo.objectWillChange,
            chapterRepo.objectWillChange,
            assignmentRepo.objectWillChange,
            submissionRepo.objectWillChange,
            groupRepo.objectWillChange,
            periodRepo.objectWillChange,
            sessionRepo.objectWillChange,
        ]
        for publisher in publishers {
            publisher
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &repositoryForwarding)
        }
    }

    // MARK: - Period & Session Management

    var periods: [Period] { periodRepo.periods }
    var sessions: [Session] { sessionRepo.sessions }

    func startListeningToPeriods(classID: String) {
        periodRepo.startListening(classID: classID)
    }

    func startListeningToPeriodsAcrossClasses() {
        let classIDs = classRepo.classes.compactMap { $0.id }
        periodRepo.startListeningAcrossClasses(classIDs: classIDs)
    }

    func startListeningToSessions(periodID: String) {
        sessionRepo.startListening(periodID: periodID)
    }

    /// Tear down period listeners installed by `startListeningToPeriods` /
    /// `startListeningToPeriodsAcrossClasses`. Live dashboard views call
    /// this in `.onDisappear` so the per-class fan-out doesn't accumulate
    /// across class switches (ISSUE-014 §4.A.3).
    func stopListeningToPeriods() {
        periodRepo.stopListening()
    }

    /// Tear down the session listener installed by `startListeningToSessions`.
    func stopListeningToSessions() {
        sessionRepo.stopListening()
    }

    func createPeriod(classID: String, name: String, startTime: Date, endTime: Date) async throws -> String {
        let period = Period(classID: classID, name: name, startTime: startTime, endTime: endTime)
        return try await periodRepo.createPeriod(period)
    }

    func createSession(periodID: String, name: String, mode: AssignmentMode, allowFreeOrder: Bool, order: Int) async throws -> String {
        let session = Session(periodID: periodID, order: order, name: name, mode: mode, allowFreeOrder: allowFreeOrder)
        return try await sessionRepo.createSession(session)
    }

    func activatePeriod(_ period: Period) async throws {
        try await periodRepo.setActive(period)
    }

    // MARK: - Group Management

    /// Groups for the currently selected class.
    var groups: [StudentGroup] { groupRepo.groups }

    func startListeningToGroups(classID: String) {
        groupRepo.startListening(classID: classID)
    }

    func createGroup(name: String, classID: String) async throws {
        let group = StudentGroup(name: name, classID: classID)
        _ = try await groupRepo.createGroup(group)
    }

    func renameGroup(_ group: StudentGroup, to newName: String) async throws {
        var updated = group
        updated.name = newName
        try await groupRepo.updateGroup(updated)
    }

    func deleteGroup(id: String, classID: String) async throws {
        try await groupRepo.deleteGroup(id: id, classID: classID)
    }

    func addStudent(_ studentID: String, toGroup groupID: String, classID: String) async throws {
        try await groupRepo.addStudent(studentID: studentID, toGroup: groupID, classID: classID)
    }

    func removeStudent(_ studentID: String, fromGroup groupID: String, classID: String) async throws {
        try await groupRepo.removeStudent(studentID: studentID, fromGroup: groupID, classID: classID)
    }

    /// Which view model currently owns the shared repositories' listeners.
    /// A language switch rebuilds the teacher view: the new view model
    /// starts listening before the old one's view disappears, so the old
    /// one must not tear the listeners down.
    private static var listeningOwner: ObjectIdentifier?

    /// Start all listeners for a teacher session.
    func startListening(teacherID: String) {
        Self.listeningOwner = ObjectIdentifier(self)
        classRepo.startListening(teacherID: teacherID)
        exerciseRepo.startListening(teacherID: teacherID)

        // Cross-class chain that powers the submission inbox:
        //   classRepo.classes  ->  assignmentRepo.teacherAssignments
        //                      ->  submissionRepo.submissions
        // Each upstream change re-arms the next listener in the chain.
        classRepo.$classes
            .map { $0.compactMap(\.id) }
            .removeDuplicates()
            .sink { [weak self] classIDs in
                guard let self = self else { return }
                self.assignmentRepo.startListeningAcrossClasses(classIDs: classIDs)
                Task { await self.refreshStudentDirectory(classIDs: classIDs) }
                Task { await self.chapterRepo.loadCompetencyLabels(classIDs: classIDs) }
            }
            .store(in: &cancellables)

        assignmentRepo.$teacherAssignments
            .map { $0.compactMap(\.id) }
            .removeDuplicates()
            .sink { [weak self] assignmentIDs in
                self?.submissionRepo.startListeningForTeacher(classAssignmentIDs: assignmentIDs)
            }
            .store(in: &cancellables)
    }

    /// Start listeners for a specific class detail view.
    func selectClass(_ classID: String) {
        selectedClassID = classID
        studentRepo.startListening(classID: classID)
        chapterRepo.startListening(classID: classID)
        assignmentRepo.startListening(classID: classID)
    }

    func stopListening() {
        cancellables.removeAll()
        guard Self.listeningOwner == ObjectIdentifier(self) else { return }
        Self.listeningOwner = nil
        classRepo.stopListening()
        studentRepo.stopListening()
        exerciseRepo.stopListening()
        chapterRepo.stopListening()
        assignmentRepo.stopListening()
        submissionRepo.stopListening()
    }

    /// One-shot fetch of all students across the teacher's classes. Used by
    /// the submission inbox to display student names regardless of which
    /// class is currently selected. Best-effort — failures are logged and
    /// the inbox falls back to the student ID prefix.
    ///
    /// The previous implementation walked classIDs sequentially (5 classes
    /// → 5 RTTs); a TaskGroup fires the fetches in parallel for one
    /// effective RTT. The repository call itself is @MainActor isolated
    /// so we capture it before entering the group and dispatch from there.
    private func refreshStudentDirectory(classIDs: [String]) async {
        let repo = self.studentRepo
        let perClass: [(String, [Student])] = await withTaskGroup(of: (String, [Student]).self) { group in
            for classID in classIDs {
                group.addTask {
                    do {
                        let students = try await repo.getStudents(classID: classID)
                        return (classID, students)
                    } catch {
                        print("Erreur chargement annuaire élèves (\(classID)): \(error.localizedDescription)")
                        return (classID, [])
                    }
                }
            }
            var collected: [(String, [Student])] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }
        var directory: [String: Student] = [:]
        for (_, students) in perClass {
            for student in students {
                if let id = student.id {
                    directory[id] = student
                }
            }
        }
        self.studentDirectory = directory
    }

    // MARK: - Class Management

    func addClass(name: String, studentsText: String) async throws {
        guard let teacherID = AuthenticationService.shared.currentUser?.uid else {
            throw TeacherError.notAuthenticated
        }

        let classCode = try await ClassCodeService.shared.generateUniqueCode()
        let newClass = ClassRoom(
            name: name,
            classCode: classCode,
            teacherID: teacherID
        )

        let classID = try await classRepo.createClass(newClass)

        // Parse and add students
        let students = StudentImportParser.parse(studentsText)
        for student in students {
            _ = try await studentRepo.addStudent(student, classID: classID)
        }
    }

    func updateClass(_ classRoom: ClassRoom) async throws {
        try await classRepo.updateClass(classRoom)
    }

    /// Deletes the class and everything in it (server-side cascade).
    func deleteClass(id: String) async throws {
        try await DataDeletionService.shared.deleteClass(id: id)
    }

    // MARK: - Live: extra exercise for one student

    enum PushExerciseError: LocalizedError {
        case noActiveAssignment
        var errorDescription: String? {
            "Aucun devoir actif dans cette classe : créez ou activez un devoir pour envoyer un exercice.".tr
        }
    }

    /// Send one more exercise to a student during the lesson. It is added to
    /// the class's active assignment — the one the student is working on
    /// when there is one — targeted at that student only, after the existing
    /// exercises. (The student app reads assignments; pushing into a
    /// Period/Session, as before, wrote data no student ever saw.)
    func pushExercise(_ exerciseID: String, to studentID: String, classID: String) async throws {
        let active = assignmentRepo.assignments
            .filter { $0.classID == classID && $0.isActive }
            .sorted { $0.createdAt > $1.createdAt }
        let working = submissionRepo.submissions
            .filter { $0.studentID == studentID && $0.classID == classID }
            .sorted { $0.timestamp > $1.timestamp }
            .compactMap { submission in active.first { $0.id == submission.assignmentID } }
            .first
        guard let assignment = working ?? active.first, let assignmentID = assignment.id else {
            throw PushExerciseError.noActiveAssignment
        }
        let existing = try await assignmentRepo.getAssignmentExercises(assignmentID: assignmentID)
        let extra = AssignmentExercise(
            assignmentID: assignmentID,
            exerciseID: exerciseID,
            order: (existing.map(\.order).max() ?? 0) + 1,
            targetStudentIDs: [studentID]
        )
        _ = try await assignmentRepo.addExerciseToAssignment(extra, assignmentID: assignmentID)
    }

    // MARK: - Student Management

    func addStudent(firstName: String, lastName: String, classID: String, level: Int? = nil) async throws {
        let student = Student(firstName: firstName, lastName: lastName, classID: classID, level: level)
        _ = try await studentRepo.addStudent(student, classID: classID)
    }

    func updateStudent(_ student: Student) async throws {
        guard let classID = student.classID else { return }
        try await studentRepo.updateStudent(student, classID: classID)
    }

    /// Erases the student and all their work (server-side cascade). Deleting
    /// only the roster doc used to leave their submissions and drawings.
    func deleteStudent(id: String, classID: String) async throws {
        try await DataDeletionService.shared.deleteStudent(id: id, classID: classID)
    }

    /// Reset a student's device so they can re-link from a different iPad.
    func resetStudentDevice(studentID: String, classID: String) async throws {
        try await studentRepo.resetDeviceLink(studentID: studentID, classID: classID)
    }

    // MARK: - Exercise Management

    func addExercise(_ exercise: Exercise) async throws {
        _ = try await exerciseRepo.createExercise(exercise)
    }

    func updateExercise(_ exercise: Exercise) async throws {
        try await exerciseRepo.updateExercise(exercise)
    }

    /// Number of the teacher's assignments that include this exercise, so
    /// deleting it can warn that students will lose it.
    func assignmentCount(usingExercise exerciseID: String) async -> Int {
        var count = 0
        for assignment in assignmentRepo.teacherAssignments {
            guard let assignmentID = assignment.id,
                  let exercises = try? await assignmentRepo.getAssignmentExercises(assignmentID: assignmentID)
            else { continue }
            if exercises.contains(where: { $0.exerciseID == exerciseID }) { count += 1 }
        }
        return count
    }

    func deleteExercise(id: String) async throws {
        try await exerciseRepo.deleteExercise(id: id)
    }

    // MARK: - Chapter Management

    func addChapter(name: String, classID: String) async throws {
        let order = chapterRepo.chapters.count
        let chapter = Chapter(name: name, order: order, classID: classID)
        _ = try await chapterRepo.createChapter(chapter, classID: classID)
    }

    func updateChapter(_ chapter: Chapter) async throws {
        guard let classID = selectedClassID else { return }
        try await chapterRepo.updateChapter(chapter, classID: classID)
    }

    func deleteChapter(id: String) async throws {
        guard let classID = selectedClassID else { return }
        try await chapterRepo.deleteChapter(id: id, classID: classID)
    }

    // MARK: - Competency Management

    func addCompetency(label: String, chapterID: String) async throws {
        guard let classID = selectedClassID else { return }
        let competency = Competency(label: label, chapterID: chapterID)
        _ = try await chapterRepo.createCompetency(competency, classID: classID, chapterID: chapterID)
    }

    func deleteCompetency(id: String, chapterID: String) async throws {
        guard let classID = selectedClassID else { return }
        try await chapterRepo.deleteCompetency(id: id, classID: classID, chapterID: chapterID)
    }

    // MARK: - Assignment Management

    func createAssignment(
        classID: String,
        mode: AssignmentMode,
        name: String? = nil,
        exercises: [(exerciseID: String, order: Int, targetStudentIDs: [String]?, groupName: String?)]
    ) async throws {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let assignment = Assignment(
            classID: classID,
            mode: mode,
            name: (trimmedName?.isEmpty ?? true) ? nil : trimmedName
        )
        let assignmentID = try await assignmentRepo.createAssignment(assignment)

        for ex in exercises {
            let ae = AssignmentExercise(
                assignmentID: assignmentID,
                exerciseID: ex.exerciseID,
                order: ex.order,
                targetStudentIDs: ex.targetStudentIDs,
                targetGroupName: ex.groupName
            )
            _ = try await assignmentRepo.addExerciseToAssignment(ae, assignmentID: assignmentID)
        }
    }

    func toggleAssignmentActive(_ assignment: Assignment) async throws {
        guard let id = assignment.id else { return }
        try await assignmentRepo.setActive(!assignment.isActive, assignmentID: id)
    }

    // MARK: - Image Upload

    /// Upload an image to Cloud Storage and return the storage path.
    func uploadExerciseImage(_ data: Data) async throws -> String {
        let imageID = UUID().uuidString
        let path = "exercises/\(imageID).jpg"
        return try await DataService.shared.uploadData(data, path: path)
    }

    // MARK: - Errors

    enum TeacherError: LocalizedError {
        case notAuthenticated
        case noClassAvailable
        case studentNotFound

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Vous devez être connecté."
            case .noClassAvailable: return "Aucune classe disponible."
            case .studentNotFound: return "Élève introuvable."
            }
        }
    }
}

// MARK: - Student Import Parser

/// Utility for parsing student lists from various formats (paste, CSV, manual).
struct StudentImportParser {

    /// Parse a text block into Student objects.
    /// Supports tab-separated, comma-separated, semicolon-separated, and space-separated formats.
    /// Auto-detects French headers (nom, prénom) to determine column order.
    static func parse(_ text: String) -> [Student] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return [] }

        // Detect separator
        let separator = detectSeparator(in: lines)

        // Detect if first line is a header and determine column order
        let (startIndex, lastNameFirst) = detectHeader(lines: lines, separator: separator)

        var students: [Student] = []
        for i in startIndex..<lines.count {
            let components = lines[i].components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard components.count >= 2 else { continue }

            let firstName: String
            let lastName: String
            if lastNameFirst {
                lastName = components[0]
                firstName = components[1]
            } else {
                firstName = components[0]
                lastName = components.dropFirst().joined(separator: " ")
            }

            students.append(Student(firstName: firstName, lastName: lastName))
        }

        return students
    }

    private static func detectSeparator(in lines: [String]) -> String {
        let tabCount = lines.reduce(0) { $0 + $1.filter { $0 == "\t" }.count }
        let semiCount = lines.reduce(0) { $0 + $1.filter { $0 == ";" }.count }
        let commaCount = lines.reduce(0) { $0 + $1.filter { $0 == "," }.count }

        if tabCount >= lines.count { return "\t" }
        if semiCount >= lines.count { return ";" }
        if commaCount >= lines.count { return "," }
        return " "
    }

    private static func detectHeader(lines: [String], separator: String) -> (startIndex: Int, lastNameFirst: Bool) {
        guard let first = lines.first?.lowercased() else { return (0, false) }

        let headerKeywords = ["nom", "prénom", "prenom", "name", "firstname", "lastname", "surname"]
        let isHeader = headerKeywords.contains(where: { first.contains($0) })

        if !isHeader { return (0, false) }

        // Determine column order from header
        let columns = first.components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        let lastNameFirst = columns.first.map { col in
            col.contains("nom") && !col.contains("prénom") && !col.contains("prenom")
        } ?? false

        return (1, lastNameFirst)
    }
}

// MARK: - Collection Helpers

extension Collection {
    var isNilOrEmpty: Bool {
        return self.isEmpty
    }
}

extension Optional where Wrapped: Collection {
    var isNilOrEmpty: Bool {
        return self?.isEmpty ?? true
    }
}
