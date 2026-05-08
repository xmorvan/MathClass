//
//  StudentView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.11.2024.
//

import SwiftUI

/// Student view for iPad.
/// Shows active assignments, exercises within them, progress indicators.
struct StudentView: View {
    @StateObject private var viewModel: StudentViewModel
    @ObservedObject private var sessionManager = StudentSessionManager.shared
    @State private var showingLogoutConfirmation = false
    @State private var showAssignmentPicker = false

    init(studentID: String, classID: String) {
        _viewModel = StateObject(wrappedValue: StudentViewModel(studentID: studentID, classID: classID))
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top navigation bar
                studentNavBar

                // Progress bar
                if !viewModel.assignedExercises.isEmpty {
                    progressBar
                }

                // Main content
                mainContent(size: geometry.size)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .edgesIgnoringSafeArea(.bottom)
        .onAppear {
            viewModel.startListening()
            Task { await viewModel.loadAssignedExercises() }
        }
        .onDisappear {
            viewModel.stopListening()
        }
        .alert("Déconnexion".tr, isPresented: $showingLogoutConfirmation) {
            Button("Annuler".tr, role: .cancel) {}
            Button("Déconnecter".tr, role: .destructive) {
                sessionManager.logout()
            }
        } message: {
            Text("Voulez-vous vraiment vous déconnecter ?".tr)
        }
        .sheet(isPresented: $showAssignmentPicker) {
            assignmentPickerSheet
        }
    }

    // MARK: - Navigation Bar

    private var studentNavBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(sessionManager.currentStudent?.fullName ?? "Élève")
                    .font(.title2)
                    .bold()

                if let assignment = viewModel.selectedAssignment {
                    Text(assignment.mode.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Assignment picker (if multiple)
            if viewModel.activeAssignments.count > 1 {
                Button {
                    showAssignmentPicker = true
                } label: {
                    Label("Devoirs".tr, systemImage: "list.bullet")
                }
                .buttonStyle(.bordered)
            }

            // Reload
            Button {
                Task { await viewModel.loadAssignedExercises() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            // Logout
            Button {
                showingLogoutConfirmation = true
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.08), radius: 2, y: 1)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Exercice \(viewModel.currentExerciseIndex + 1) / \(viewModel.assignedExercises.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(viewModel.completedCount) terminé\(viewModel.completedCount > 1 ? "s" : "")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Exercise indicators
            HStack(spacing: 4) {
                ForEach(Array(viewModel.assignedExercises.enumerated()), id: \.element.id) { index, exercise in
                    exerciseIndicator(index: index, exercise: exercise)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    private func exerciseIndicator(index: Int, exercise: Exercise) -> some View {
        let isCompleted = exercise.id.map { viewModel.isExerciseCompleted($0) } ?? false
        let isCurrent = index == viewModel.currentExerciseIndex

        return Button {
            viewModel.selectExercise(at: index)
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(indicatorColor(completed: isCompleted, current: isCurrent))
                .frame(height: 6)
                .overlay(
                    isCurrent
                        ? RoundedRectangle(cornerRadius: 4).stroke(Color.blue, lineWidth: 2)
                        : nil
                )
        }
        .buttonStyle(.plain)
    }

    private func indicatorColor(completed: Bool, current: Bool) -> Color {
        if completed { return .green }
        if current { return .blue.opacity(0.4) }
        return .gray.opacity(0.3)
    }

    // MARK: - Main Content

    @ViewBuilder
    private func mainContent(size: CGSize) -> some View {
        if viewModel.isLoading {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Chargement des exercices…".tr)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let currentExercise = viewModel.currentExercise {
            // ExerciseView now owns its own SubmissionViewModel and drives
            // the verify → recognize → confirm → submit → feedback pipeline
            // through SubmissionViewModel — no more legacy direct-submit
            // closure that bypassed the whole correction flow.
            ExerciseView(
                exercise: currentExercise,
                studentViewModel: viewModel,
                assignmentMode: viewModel.currentMode
            )
            .id(currentExercise.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !viewModel.assignedExercises.isEmpty {
            allCompletedView
        } else {
            noAssignmentsView
        }
    }

    // MARK: - Empty States

    private var allCompletedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("Bravo !".tr)
                .font(.largeTitle)
                .bold()

            Text("Vous avez terminé tous les exercices\nde ce devoir.".tr)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await viewModel.loadAssignedExercises() }
            } label: {
                Label("Vérifier les nouveaux devoirs".tr, systemImage: "arrow.clockwise")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noAssignmentsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Aucun devoir actif".tr)
                .font(.title2)

            Text("Votre professeur n'a pas encore\nassigné de devoir à votre classe.".tr)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await viewModel.loadAssignedExercises() }
            } label: {
                Label("Recharger".tr, systemImage: "arrow.clockwise")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Assignment Picker

    private var assignmentPickerSheet: some View {
        NavigationView {
            List(viewModel.activeAssignments) { assignment in
                Button {
                    Task {
                        await viewModel.loadExercises(for: assignment)
                    }
                    showAssignmentPicker = false
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(assignment.mode.displayName)
                                .font(.headline)
                            Text(assignment.createdAt.timeElapsed())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if assignment.id == viewModel.selectedAssignment?.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Devoirs actifs".tr)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer".tr) { showAssignmentPicker = false }
                }
            }
        }
    }
}
