//
//  TeacherView_macOS.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.11.2024.
//

import SwiftUI
import AppKit

/// Teacher dashboard for macOS.
/// Sidebar: Classes, Exercices, Devoirs, Soumissions, En direct, Statistiques.
struct TeacherView_macOS: View {
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var viewModel = TeacherViewModel()
    @State private var selectedSidebar: Int? = 1
    @State private var showLogoutAlert = false
    @State private var showingProfile = false

    var body: some View {
        NavigationSplitView {
            VStack {
                List(selection: $selectedSidebar) {
                    NavigationLink(value: 1) {
                        Label("Classes".tr, systemImage: "person.3")
                    }
                    NavigationLink(value: 2) {
                        Label("Exercices".tr, systemImage: "book")
                    }
                    NavigationLink(value: 3) {
                        Label("Devoirs".tr, systemImage: "tray.full")
                    }
                    NavigationLink(value: 5) {
                        Label("Soumissions".tr, systemImage: "tray.and.arrow.down")
                    }
                    NavigationLink(value: 6) {
                        Label("En direct".tr, systemImage: "dot.radiowaves.left.and.right")
                    }
                    NavigationLink(value: 4) {
                        Label("Statistiques".tr, systemImage: "chart.bar")
                    }
                }
                .listStyle(SidebarListStyle())

                Spacer()

                // User account info and logout button
                HStack {
                    if let email = authService.currentUser?.email {
                        Text(email)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Button {
                        showLogoutAlert = true
                    } label: {
                        Label("Déconnexion".tr, systemImage: "rectangle.portrait.and.arrow.right")
                            .labelStyle(.iconOnly)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .alert("Déconnexion".tr, isPresented: $showLogoutAlert) {
                Button("Annuler".tr, role: .cancel) { }
                Button("Déconnexion".tr, role: .destructive) {
                    do {
                        try authService.signOut()
                    } catch {
                        print("Erreur déconnexion: \(error.localizedDescription)")
                    }
                }
            } message: {
                Text("Êtes-vous sûr de vouloir vous déconnecter ?".tr)
            }
        } detail: {
            Group {
                switch selectedSidebar {
                case 1:
                    ClassManagementView_macOS(viewModel: viewModel)
                case 2:
                    ExerciseListView_macOS(viewModel: viewModel)
                case 3:
                    AssignmentListView_macOS(viewModel: viewModel)
                case 4:
                    StatisticsView_macOS(viewModel: viewModel)
                case 5:
                    SubmissionInboxView_macOS(viewModel: viewModel)
                case 6:
                    LiveDashboardView_macOS(viewModel: viewModel)
                default:
                    Text("Sélectionnez une section".tr)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if let email = authService.currentUser?.email {
                            Text(LocalizationManager.shared.format("Connecté : %@", email))
                            Divider()
                        }
                        Button {
                            showingProfile = true
                        } label: {
                            Label("Mon profil".tr, systemImage: "person.text.rectangle")
                        }
                        Divider()
                        Button("Déconnexion".tr, role: .destructive) {
                            showLogoutAlert = true
                        }
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingProfile) {
            TeacherProfileView_macOS()
        }
        .onAppear {
            if LocalizationManager.shared.reopenProfileAfterRebuild {
                LocalizationManager.shared.reopenProfileAfterRebuild = false
                showingProfile = true
            }
            if let teacherID = authService.currentUser?.uid {
                viewModel.startListening(teacherID: teacherID)
            }
        }
        .onDisappear {
            viewModel.stopListening()
        }
    }
}

// MARK: - Exercise List View (macOS)

struct ExerciseListView_macOS: View {
    @ObservedObject var viewModel: TeacherViewModel
    @StateObject private var windowManager = ExerciseWindowManager()
    @State private var selectedExerciseID: String?
    @State private var showingDeleteAlert = false
    @State private var exerciseToDelete: Exercise?
    @State private var exerciseInUseCount: Int = 0

    var body: some View {
        HSplitView {
            // Left: exercise table
            VStack {
                List(viewModel.exercises, selection: $selectedExerciseID) { exercise in
                    HStack {
                        Text(exercise.displayTitle)
                        Spacer()
                        Text(String(repeating: "⭐", count: exercise.difficultyLevel))
                    }
                    .tag(exercise.id)
                    .contextMenu {
                        Button {
                            windowManager.openEditExerciseWindow(exercise: exercise, viewModel: viewModel)
                        } label: {
                            Label("Modifier".tr, systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            Task {
                                exerciseInUseCount = await viewModel.assignmentCount(usingExercise: exercise.id ?? "")
                                exerciseToDelete = exercise
                                showingDeleteAlert = true
                            }
                        } label: {
                            Label("Supprimer".tr, systemImage: "trash")
                        }
                    }
                }
            }
            .frame(minWidth: 240, idealWidth: 320, maxWidth: 420)

            // Right: exercise detail with KaTeX preview
            if let exerciseID = selectedExerciseID,
               let exercise = viewModel.exercises.first(where: { $0.id == exerciseID }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(exercise.displayTitle)
                                .font(.title2)
                                .bold()
                            Spacer()
                            HStack(spacing: 2) {
                                ForEach(1...5, id: \.self) { level in
                                    Image(systemName: level <= exercise.difficultyLevel ? "star.fill" : "star")
                                        .foregroundColor(level <= exercise.difficultyLevel ? .yellow : .gray)
                                        .font(.caption)
                                }
                            }
                        }

                        Text("Énoncé".tr)
                            .font(.headline)
                        KaTeXView(content: exercise.statement, mode: .preview, fontSize: 18, minHeight: 80)
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(8)

                        if !exercise.expectedAnswer.isEmpty {
                            Text("Réponse attendue".tr)
                                .font(.headline)
                            KaTeXView(
                                content: "$\(exercise.expectedAnswer)$",
                                mode: .preview,
                                fontSize: 16,
                                minHeight: 40
                            )
                        }

                        if let imageURL = exercise.statementImageURL {
                            Text("Image source".tr)
                                .font(.headline)
                            AsyncImageFromStorage(path: imageURL)
                        }

                        HStack {
                            Button {
                                windowManager.openEditExerciseWindow(exercise: exercise, viewModel: viewModel)
                            } label: {
                                Label("Modifier".tr, systemImage: "pencil")
                            }
                            .buttonStyle(.bordered)
                        }

                        Spacer()
                    }
                    .padding()
                }
                .id(exerciseID)
            } else {
                Text("Sélectionnez un exercice pour voir les détails".tr)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    windowManager.openAddExerciseWindow(with: viewModel)
                } label: {
                    Label("Ajouter un exercice".tr, systemImage: "plus")
                }
            }
        }
        .alert("Supprimer l'exercice".tr, isPresented: $showingDeleteAlert) {
            Button("Annuler".tr, role: .cancel) { }
            Button("Supprimer".tr, role: .destructive) {
                if let exercise = exerciseToDelete, let id = exercise.id {
                    Task {
                        try? await viewModel.deleteExercise(id: id)
                    }
                }
            }
        } message: {
            Text(deleteExerciseMessage)
        }
    }

    private var deleteExerciseMessage: String {
        exerciseInUseCount > 0
            ? LocalizationManager.shared.format(
                "Cet exercice est utilisé dans %@ devoir(s) : les élèves ne le verront plus et ses copies perdront leur énoncé.",
                String(exerciseInUseCount))
            : "L'exercice sera retiré de votre bibliothèque.".tr
    }
}
