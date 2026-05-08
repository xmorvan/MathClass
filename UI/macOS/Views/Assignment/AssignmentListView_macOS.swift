//
//  AssignmentListView_macOS.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import SwiftUI

/// Assignment list and management view for the macOS teacher dashboard.
/// Shows active and past assignments, allows creation and activation/deactivation.
struct AssignmentListView_macOS: View {
    @ObservedObject var viewModel: TeacherViewModel
    @StateObject private var assignmentVM: AssignmentViewModel
    @State private var showingCreateSheet = false
    @State private var selectedAssignmentID: String?
    @State private var selectedClassID: String?
    @State private var showingDeleteAlert = false
    @State private var assignmentToDelete: Assignment?

    init(viewModel: TeacherViewModel) {
        self.viewModel = viewModel
        _assignmentVM = StateObject(wrappedValue: AssignmentViewModel(teacherViewModel: viewModel))
    }

    var body: some View {
        HSplitView {
            // Left: Assignment list
            VStack(alignment: .leading, spacing: 0) {
                assignmentListHeader

                Divider()

                if viewModel.assignments.isEmpty {
                    emptyState
                } else {
                    assignmentList
                }
            }
            .frame(minWidth: 300)

            // Right: Assignment detail
            if let assignmentID = selectedAssignmentID,
               let assignment = viewModel.assignments.first(where: { $0.id == assignmentID }) {
                AssignmentDetailView_macOS(
                    assignment: assignment,
                    viewModel: viewModel,
                    assignmentVM: assignmentVM
                )
            } else {
                Text("Sélectionnez un devoir pour voir les détails".tr)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateAssignmentView_macOS(
                viewModel: viewModel,
                assignmentVM: assignmentVM,
                onDismiss: { showingCreateSheet = false }
            )
            .frame(minWidth: 700, minHeight: 550)
        }
        .alert("Supprimer le devoir".tr, isPresented: $showingDeleteAlert) {
            Button("Annuler".tr, role: .cancel) { }
            Button("Supprimer".tr, role: .destructive) {
                if let assignment = assignmentToDelete {
                    Task { await assignmentVM.deleteAssignment(assignment) }
                }
            }
        } message: {
            Text("Êtes-vous sûr de vouloir supprimer ce devoir et tous ses exercices associés ?".tr)
        }
        .onAppear {
            if selectedClassID == nil, let first = viewModel.classes.first {
                selectedClassID = first.id
            }
            if let classID = selectedClassID {
                viewModel.assignmentRepo.startListening(classID: classID)
            }
        }
        .onChange(of: selectedClassID) { _, newID in
            if let classID = newID {
                viewModel.assignmentRepo.startListening(classID: classID)
            }
        }
    }

    // MARK: - Header

    private var assignmentListHeader: some View {
        HStack {
            Text("Devoirs".tr)
                .font(.title2)
                .bold()

            Spacer()

            Picker("Classe".tr, selection: $selectedClassID) {
                Text("Sélectionner une classe".tr).tag(nil as String?)
                ForEach(viewModel.classes) { classroom in
                    Text(classroom.name).tag(classroom.id as String?)
                }
            }
            .frame(width: 200)

            Button {
                assignmentVM.resetCreation()
                showingCreateSheet = true
            } label: {
                Label("Nouveau devoir".tr, systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Aucun devoir".tr)
                .font(.headline)
            Text("Créez un devoir pour assigner des exercices à vos élèves.".tr)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Créer un devoir".tr) {
                assignmentVM.resetCreation()
                showingCreateSheet = true
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Assignment List

    private var assignmentList: some View {
        List(selection: $selectedAssignmentID) {
            if !assignmentVM.activeAssignments.isEmpty {
                Section("Actifs".tr) {
                    ForEach(assignmentVM.activeAssignments) { assignment in
                        assignmentRow(assignment)
                            .tag(assignment.id)
                    }
                }
            }

            if !assignmentVM.pastAssignments.isEmpty {
                Section("Terminés".tr) {
                    ForEach(assignmentVM.pastAssignments) { assignment in
                        assignmentRow(assignment)
                            .tag(assignment.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func assignmentRow(_ assignment: Assignment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: assignment.mode.iconName)
                    .foregroundColor(assignment.mode.color)
                Text(assignment.mode.displayName)
                    .font(.headline)
                Spacer()
                if assignment.isActive {
                    Image(systemName: "circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 8))
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

            let exerciseCount = assignmentVM.exercisesForAssignment(assignment.id ?? "").count
            Text("\(exerciseCount) exercice\(exerciseCount != 1 ? "s" : "")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                Task { await assignmentVM.toggleActive(assignment) }
            } label: {
                Label(
                    assignment.isActive ? "Désactiver" : "Activer",
                    systemImage: assignment.isActive ? "pause.circle" : "play.circle"
                )
            }

            Divider()

            Button(role: .destructive) {
                assignmentToDelete = assignment
                showingDeleteAlert = true
            } label: {
                Label("Supprimer".tr, systemImage: "trash")
            }
        }
    }
}

// MARK: - Assignment Detail View

struct AssignmentDetailView_macOS: View {
    let assignment: Assignment
    @ObservedObject var viewModel: TeacherViewModel
    @ObservedObject var assignmentVM: AssignmentViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: assignment.mode.iconName)
                                .font(.title2)
                                .foregroundColor(assignment.mode.color)
                            Text(assignment.mode.displayName)
                                .font(.title2)
                                .bold()
                        }
                        Text(assignmentVM.className(for: assignment.classID))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        statusBadge
                        Text(assignment.createdAt.formatted(date: .long, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Mode description
                modeDescription

                Divider()

                // Exercise list
                exerciseList

                Spacer()
            }
            .padding()
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(assignment.isActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(assignment.isActive ? "Actif" : "Terminé")
                .font(.caption)
                .foregroundColor(assignment.isActive ? .green : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill((assignment.isActive ? Color.green : Color.gray).opacity(0.1))
        )
    }

    private var modeDescription: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mode".tr)
                .font(.headline)

            HStack(spacing: 16) {
                InfoBadge(
                    title: "Feedback",
                    value: assignment.mode.showsFeedback ? "Oui" : "Non",
                    color: assignment.mode.showsFeedback ? .green : .orange
                )
                InfoBadge(
                    title: "2e chance",
                    value: assignment.mode.allows2ndChance ? "Oui" : "Non",
                    color: assignment.mode.allows2ndChance ? .green : .orange
                )
                InfoBadge(
                    title: "Erreur détaillée",
                    value: assignment.mode.showsErrorStep ? "Oui" : "Non",
                    color: assignment.mode.showsErrorStep ? .green : .gray
                )
            }
        }
    }

    private var exerciseList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercices".tr)
                .font(.headline)

            let assignmentExercises = assignmentVM.exercisesForAssignment(assignment.id ?? "")

            if assignmentExercises.isEmpty {
                Text("Aucun exercice assigné.".tr)
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                ForEach(assignmentExercises) { ae in
                    HStack {
                        Text("\(ae.order).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 30, alignment: .trailing)

                        if let exercise = assignmentVM.exercise(byID: ae.exerciseID) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.title)
                                    .font(.body)
                                HStack(spacing: 2) {
                                    ForEach(1...5, id: \.self) { level in
                                        Image(systemName: level <= exercise.difficultyLevel ? "star.fill" : "star")
                                            .foregroundColor(level <= exercise.difficultyLevel ? .yellow : .gray.opacity(0.3))
                                            .font(.system(size: 10))
                                    }
                                }
                            }
                        } else {
                            Text("Exercice introuvable".tr)
                                .foregroundColor(.red)
                                .font(.caption)
                        }

                        Spacer()

                        if let group = ae.targetGroupName {
                            Text(group)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
                }
            }
        }
    }
}

// MARK: - Info Badge

private struct InfoBadge: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .bold()
                .foregroundColor(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }
}

