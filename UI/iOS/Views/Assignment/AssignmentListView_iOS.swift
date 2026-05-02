//
//  AssignmentListView_iOS.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import SwiftUI

/// Assignment list for iPad teacher dashboard.
/// Shows active and past assignments, allows creation and management.
struct AssignmentListView_iOS: View {
    @ObservedObject var viewModel: TeacherViewModel
    @StateObject private var assignmentVM: AssignmentViewModel
    @State private var showingCreateSheet = false
    @State private var selectedAssignment: Assignment?
    @State private var showingDeleteAlert = false
    @State private var assignmentToDelete: Assignment?

    init(viewModel: TeacherViewModel) {
        self.viewModel = viewModel
        _assignmentVM = StateObject(wrappedValue: AssignmentViewModel(teacherViewModel: viewModel))
    }

    var body: some View {
        Group {
            if viewModel.assignments.isEmpty {
                emptyState
            } else {
                assignmentList
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            NavigationView {
                CreateAssignmentView_iOS(
                    viewModel: viewModel,
                    assignmentVM: assignmentVM,
                    onDismiss: { showingCreateSheet = false }
                )
            }
        }
        .sheet(item: $selectedAssignment) { assignment in
            NavigationView {
                AssignmentDetailView_iOS(
                    assignment: assignment,
                    viewModel: viewModel,
                    assignmentVM: assignmentVM
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    assignmentVM.resetCreation()
                    showingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("Supprimer le devoir", isPresented: $showingDeleteAlert) {
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                if let assignment = assignmentToDelete {
                    Task { await assignmentVM.deleteAssignment(assignment) }
                }
            }
        } message: {
            Text("Êtes-vous sûr de vouloir supprimer ce devoir ?")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Aucun devoir")
                .font(.headline)
            Text("Créez un devoir pour assigner des exercices à vos élèves.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Créer un devoir") {
                assignmentVM.resetCreation()
                showingCreateSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Assignment List

    private var assignmentList: some View {
        List {
            if !assignmentVM.activeAssignments.isEmpty {
                Section("Actifs") {
                    ForEach(assignmentVM.activeAssignments) { assignment in
                        assignmentRow(assignment)
                            .onTapGesture { selectedAssignment = assignment }
                    }
                }
            }

            if !assignmentVM.pastAssignments.isEmpty {
                Section("Terminés") {
                    ForEach(assignmentVM.pastAssignments) { assignment in
                        assignmentRow(assignment)
                            .onTapGesture { selectedAssignment = assignment }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func assignmentRow(_ assignment: Assignment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: assignment.mode.iconName)
                    .foregroundColor(assignment.mode.color)
                Text(assignment.mode.displayName)
                    .font(.headline)
                Spacer()
                if assignment.isActive {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                }
            }

            HStack {
                Text(assignmentVM.className(for: assignment.classID))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(assignment.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Avoid passing an empty fallback ID into the lookup, which used
            // to silently report 0 exercises if a Firestore document was
            // momentarily missing its @DocumentID during a snapshot pass.
            let exerciseCount = assignment.id.map {
                assignmentVM.exercisesForAssignment($0).count
            } ?? 0
            Text("\(exerciseCount) exercice\(exerciseCount != 1 ? "s" : "")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                assignmentToDelete = assignment
                showingDeleteAlert = true
            } label: {
                Label("Supprimer", systemImage: "trash")
            }

            Button {
                Task { await assignmentVM.toggleActive(assignment) }
            } label: {
                Label(
                    assignment.isActive ? "Désactiver" : "Activer",
                    systemImage: assignment.isActive ? "pause.circle" : "play.circle"
                )
            }
            .tint(assignment.isActive ? .orange : .green)
        }
    }
}

// MARK: - Assignment Detail View (iOS)

struct AssignmentDetailView_iOS: View {
    let assignment: Assignment
    @ObservedObject var viewModel: TeacherViewModel
    @ObservedObject var assignmentVM: AssignmentViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            Section("Informations") {
                HStack {
                    Text("Mode")
                    Spacer()
                    Label(assignment.mode.displayName, systemImage: assignment.mode.iconName)
                        .foregroundColor(assignment.mode.color)
                }

                HStack {
                    Text("Classe")
                    Spacer()
                    Text(assignmentVM.className(for: assignment.classID))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Statut")
                    Spacer()
                    Text(assignment.isActive ? "Actif" : "Terminé")
                        .foregroundColor(assignment.isActive ? .green : .secondary)
                }

                HStack {
                    Text("Créé le")
                    Spacer()
                    Text(assignment.createdAt.formatted(date: .long, time: .shortened))
                        .foregroundColor(.secondary)
                }
            }

            Section("Mode") {
                HStack {
                    Text("Feedback")
                    Spacer()
                    Text(assignment.mode.showsFeedback ? "Oui" : "Non")
                        .foregroundColor(assignment.mode.showsFeedback ? .green : .orange)
                }
                HStack {
                    Text("2e chance")
                    Spacer()
                    Text(assignment.mode.allows2ndChance ? "Oui" : "Non")
                        .foregroundColor(assignment.mode.allows2ndChance ? .green : .orange)
                }
                HStack {
                    Text("Erreur détaillée")
                    Spacer()
                    Text(assignment.mode.showsErrorStep ? "Oui" : "Non")
                        .foregroundColor(assignment.mode.showsErrorStep ? .green : .gray)
                }
            }

            Section("Exercices") {
                let exercises = assignmentVM.exercisesForAssignment(assignment.id ?? "")
                if exercises.isEmpty {
                    Text("Aucun exercice")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(exercises) { ae in
                        HStack {
                            Text("\(ae.order).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let exercise = assignmentVM.exercise(byID: ae.exerciseID) {
                                Text(exercise.title)
                            } else {
                                Text("Exercice introuvable")
                                    .foregroundColor(.red)
                            }
                            Spacer()
                            if let group = ae.targetGroupName {
                                Text(group)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Détail du devoir")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Fermer") { dismiss() }
            }
        }
    }
}

// MARK: - Create Assignment View (iOS)

struct CreateAssignmentView_iOS: View {
    @ObservedObject var viewModel: TeacherViewModel
    @ObservedObject var assignmentVM: AssignmentViewModel
    var onDismiss: () -> Void

    var body: some View {
        Form {
            Section("Classe") {
                Picker("Classe", selection: $assignmentVM.selectedClassID) {
                    Text("Sélectionner").tag(nil as String?)
                    ForEach(viewModel.classes) { classroom in
                        Text(classroom.name).tag(classroom.id as String?)
                    }
                }
                .onChange(of: assignmentVM.selectedClassID) { _, _ in
                    assignmentVM.loadStudentsForSelectedClass()
                }
            }

            Section("Mode") {
                Picker("Mode", selection: $assignmentVM.selectedMode) {
                    ForEach(AssignmentMode.allCases, id: \.self) { mode in
                        Label(mode.displayName, systemImage: mode.iconName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Exercices") {
                ForEach(assignmentVM.filteredExercises) { exercise in
                    let isSelected = assignmentVM.selectedExercises.contains { $0.exerciseID == exercise.id }
                    HStack {
                        VStack(alignment: .leading) {
                            Text(exercise.title)
                            HStack(spacing: 2) {
                                ForEach(1...5, id: \.self) { level in
                                    Image(systemName: level <= exercise.difficultyLevel ? "star.fill" : "star")
                                        .foregroundColor(level <= exercise.difficultyLevel ? .yellow : .gray.opacity(0.3))
                                        .font(.system(size: 10))
                                }
                            }
                        }
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? .green : .secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isSelected {
                            if let idx = assignmentVM.selectedExercises.firstIndex(where: { $0.exerciseID == exercise.id }) {
                                assignmentVM.removeExercise(at: IndexSet(integer: idx))
                            }
                        } else {
                            assignmentVM.addExercise(exercise)
                        }
                    }
                }
            }

            if !assignmentVM.selectedExercises.isEmpty {
                Section("Sélectionnés (\(assignmentVM.selectedExercises.count))") {
                    ForEach(Array(assignmentVM.selectedExercises.enumerated()), id: \.element.id) { index, selected in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(selected.order). \(selected.exerciseTitle)")
                                Spacer()
                                if assignmentVM.selectedMode == .differentiation {
                                    let count = selected.targetStudentIDs?.count ?? 0
                                    NavigationLink {
                                        StudentTargetingView_iOS(
                                            students: assignmentVM.studentsInSelectedClass,
                                            selectedIDs: selected.targetStudentIDs ?? [],
                                            groupName: selected.targetGroupName ?? ""
                                        ) { studentIDs, groupName in
                                            assignmentVM.setTargetStudents(
                                                exerciseIndex: index,
                                                studentIDs: studentIDs.isEmpty ? nil : studentIDs,
                                                groupName: groupName.isEmpty ? nil : groupName
                                            )
                                        }
                                    } label: {
                                        Text(count > 0 ? "\(count) élève\(count > 1 ? "s" : "")" : "Tous")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            if let group = selected.targetGroupName {
                                Text(group)
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .onMove { source, destination in
                        assignmentVM.moveExercise(from: source, to: destination)
                    }
                }
            }

            if let error = assignmentVM.error {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Nouveau devoir")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Annuler") { onDismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await assignmentVM.createAssignment()
                        if assignmentVM.error == nil {
                            onDismiss()
                        }
                    }
                } label: {
                    if assignmentVM.isCreating {
                        ProgressView()
                    } else {
                        Text("Créer")
                            .bold()
                    }
                }
                .disabled(assignmentVM.selectedClassID == nil || assignmentVM.selectedExercises.isEmpty || assignmentVM.isCreating)
            }
        }
    }
}

// MARK: - Student Targeting View (iOS)

/// View for selecting which students should receive an exercise (differentiation mode).
struct StudentTargetingView_iOS: View {
    let students: [Student]
    @State var selectedIDs: [String]
    @State var groupName: String
    var onSave: ([String], String) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section("Groupe") {
                TextField("Nom du groupe (optionnel)", text: $groupName)
            }

            Section("Élèves (vide = tous)") {
                ForEach(students) { student in
                    let isSelected = selectedIDs.contains(student.id ?? "")
                    Button {
                        toggleStudent(student)
                    } label: {
                        HStack {
                            Text(student.sortName)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isSelected ? .blue : .secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Cibler des élèves")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Appliquer") {
                    onSave(selectedIDs, groupName)
                    dismiss()
                }
            }
        }
    }

    private func toggleStudent(_ student: Student) {
        guard let studentID = student.id else { return }
        if let index = selectedIDs.firstIndex(of: studentID) {
            selectedIDs.remove(at: index)
        } else {
            selectedIDs.append(studentID)
        }
    }
}
