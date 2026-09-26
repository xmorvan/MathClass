//
//  AssignmentViewModel.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import Combine

/// ViewModel for assignment creation, management, and exercise selection.
/// Used by both the assignment list and creation views.
@MainActor
class AssignmentViewModel: ObservableObject {

    // MARK: - Published State (Creation)

    @Published var selectedClassID: String?
    @Published var selectedMode: AssignmentMode = .differentiation
    /// Optional name typed by the teacher.
    @Published var assignmentName: String = ""
    @Published var selectedExercises: [SelectedExercise] = []
    @Published var isCreating: Bool = false
    @Published var error: String?

    // MARK: - Published State (Filtering)

    @Published var filterChapterID: String?
    @Published var searchText: String = ""

    // MARK: - Dependencies

    private let teacherViewModel: TeacherViewModel
    /// Tracks the last class ID we issued a student-listener attach for, so
    /// rapid picker changes (A → B → C) don't re-attach to the same class
    /// or interleave attaches for stale selections (ISSUE-015).
    private var lastLoadedClassID: String?

    init(teacherViewModel: TeacherViewModel) {
        self.teacherViewModel = teacherViewModel
    }

    // MARK: - Data Access

    var classes: [ClassRoom] { teacherViewModel.classes }
    var exercises: [Exercise] { teacherViewModel.exercises }
    var chapters: [Chapter] { teacherViewModel.chapters }
    var assignments: [Assignment] { teacherViewModel.assignments }

    /// Active assignments.
    var activeAssignments: [Assignment] {
        assignments.filter { $0.isActive }
    }

    /// Past (inactive) assignments.
    var pastAssignments: [Assignment] {
        assignments.filter { !$0.isActive }
    }

    /// Exercises filtered by chapter and search text.
    var filteredExercises: [Exercise] {
        var result = exercises

        if let chapterID = filterChapterID {
            result = result.filter { $0.chapterID == chapterID }
        }

        if !searchText.isEmpty {
            result = result.filter { exercise in
                exercise.title.localizedCaseInsensitiveContains(searchText)
                    || exercise.statement.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    /// Students for the selected class.
    /// Triggers student loading when a class is selected for assignment creation.
    var studentsInSelectedClass: [Student] {
        guard let classID = selectedClassID else { return [] }
        return teacherViewModel.studentsInClass(classID)
    }

    /// Ensure student data is loaded for the selected class.
    /// Cheap to call repeatedly — guards against re-attaching to the same
    /// class and against a stale selection clobbering the live one
    /// (ISSUE-015). The underlying `studentRepo.startListening` also tears
    /// down its previous listener, so at most one listener is ever live.
    func loadStudentsForSelectedClass() {
        guard let classID = selectedClassID else {
            lastLoadedClassID = nil
            return
        }
        guard classID != lastLoadedClassID else { return }
        lastLoadedClassID = classID
        teacherViewModel.studentRepo.startListening(classID: classID)
    }

    /// Assignment exercises for a given assignment ID.
    func exercisesForAssignment(_ assignmentID: String) -> [AssignmentExercise] {
        teacherViewModel.assignmentRepo.assignmentExercises[assignmentID] ?? []
    }

    /// Look up an exercise by its ID.
    func exercise(byID id: String) -> Exercise? {
        exercises.first { $0.id == id }
    }

    /// Class name for a given class ID.
    func className(for classID: String) -> String {
        classes.first { $0.id == classID }?.name ?? "Classe inconnue"
    }

    // MARK: - Exercise Selection for Creation

    /// Represents an exercise selected for assignment creation.
    struct SelectedExercise: Identifiable {
        let id = UUID()
        var exerciseID: String
        var exerciseTitle: String
        var order: Int
        var targetStudentIDs: [String]?
        var targetGroupName: String?
    }

    /// Add an exercise to the selection list.
    func addExercise(_ exercise: Exercise) {
        guard let id = exercise.id else { return }
        guard !selectedExercises.contains(where: { $0.exerciseID == id }) else { return }

        let order = selectedExercises.count + 1
        selectedExercises.append(SelectedExercise(
            exerciseID: id,
            exerciseTitle: exercise.title,
            order: order
        ))
    }

    /// Remove an exercise from the selection list.
    func removeExercise(at offsets: IndexSet) {
        selectedExercises.remove(atOffsets: offsets)
        reorderExercises()
    }

    /// Move exercises to reorder.
    func moveExercise(from source: IndexSet, to destination: Int) {
        selectedExercises.move(fromOffsets: source, toOffset: destination)
        reorderExercises()
    }

    private func reorderExercises() {
        for (index, _) in selectedExercises.enumerated() {
            selectedExercises[index].order = index + 1
        }
    }

    /// Set target student IDs for an exercise (differentiation mode).
    /// An empty array is normalised to `nil` so the read path interprets it
    /// as "all students" (per `AssignmentRepository.getExercisesForStudent`),
    /// preventing the bug where deselecting every student in the targeting
    /// popover hides the exercise from everyone.
    func setTargetStudents(exerciseIndex: Int, studentIDs: [String]?, groupName: String?) {
        guard exerciseIndex < selectedExercises.count else { return }
        let normalized: [String]? = (studentIDs?.isEmpty ?? true) ? nil : studentIDs
        selectedExercises[exerciseIndex].targetStudentIDs = normalized
        selectedExercises[exerciseIndex].targetGroupName = groupName
    }

    // MARK: - Create Assignment

    func createAssignment() async {
        guard let classID = selectedClassID else {
            error = "Veuillez sélectionner une classe.".tr
            return
        }
        guard !selectedExercises.isEmpty else {
            error = "Veuillez ajouter au moins un exercice.".tr
            return
        }

        isCreating = true
        error = nil

        do {
            let exercises = selectedExercises.map { selected in
                (
                    exerciseID: selected.exerciseID,
                    order: selected.order,
                    targetStudentIDs: selected.targetStudentIDs,
                    groupName: selected.targetGroupName
                )
            }

            try await teacherViewModel.createAssignment(
                classID: classID,
                mode: selectedMode,
                name: assignmentName,
                exercises: exercises
            )

            // Reset creation state
            resetCreation()
        } catch {
            self.error = error.localizedDescription
        }

        isCreating = false
    }

    /// Reset creation state for a new assignment.
    func resetCreation() {
        selectedExercises = []
        selectedMode = .differentiation
        assignmentName = ""
        filterChapterID = nil
        searchText = ""
    }

    // MARK: - Toggle Active

    func toggleActive(_ assignment: Assignment) async {
        do {
            try await teacherViewModel.toggleAssignmentActive(assignment)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Delete Assignment

    func deleteAssignment(_ assignment: Assignment) async {
        guard let id = assignment.id else { return }
        do {
            try await teacherViewModel.assignmentRepo.deleteAssignment(id: id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
