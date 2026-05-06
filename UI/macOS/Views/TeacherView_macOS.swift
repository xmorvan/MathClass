//
//  TeacherView_macOS.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.11.2024.
//

import SwiftUI
import AppKit

/// Teacher dashboard for macOS.
/// Sidebar: Classes, Exercices, Devoirs, Statistiques.
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
                        Label("Classes", systemImage: "person.3")
                    }
                    NavigationLink(value: 2) {
                        Label("Exercices", systemImage: "book")
                    }
                    NavigationLink(value: 3) {
                        Label("Devoirs", systemImage: "tray.full")
                    }
                    NavigationLink(value: 5) {
                        Label("Soumissions", systemImage: "tray.and.arrow.down")
                    }
                    NavigationLink(value: 4) {
                        Label("Statistiques", systemImage: "chart.bar")
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
                        Label("Déconnexion", systemImage: "rectangle.portrait.and.arrow.right")
                            .labelStyle(.iconOnly)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .alert("Déconnexion", isPresented: $showLogoutAlert) {
                Button("Annuler", role: .cancel) { }
                Button("Déconnexion", role: .destructive) {
                    do {
                        try authService.signOut()
                    } catch {
                        print("Erreur déconnexion: \(error.localizedDescription)")
                    }
                }
            } message: {
                Text("Êtes-vous sûr de vouloir vous déconnecter ?")
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
                default:
                    Text("Sélectionnez une section")
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if let email = authService.currentUser?.email {
                            Text("Connecté: \(email)")
                            Divider()
                        }
                        Button {
                            showingProfile = true
                        } label: {
                            Label("Mon profil", systemImage: "person.text.rectangle")
                        }
                        Divider()
                        Button("Déconnexion", role: .destructive) {
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

    var body: some View {
        HSplitView {
            // Left: exercise table
            VStack {
                List(viewModel.exercises, selection: $selectedExerciseID) { exercise in
                    HStack {
                        Text(exercise.title)
                        Spacer()
                        Text(String(repeating: "⭐", count: exercise.difficultyLevel))
                    }
                    .tag(exercise.id)
                    .contextMenu {
                        Button {
                            windowManager.openEditExerciseWindow(exercise: exercise, viewModel: viewModel)
                        } label: {
                            Label("Modifier", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            exerciseToDelete = exercise
                            showingDeleteAlert = true
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
                }
            }

            // Right: exercise detail with KaTeX preview
            if let exerciseID = selectedExerciseID,
               let exercise = viewModel.exercises.first(where: { $0.id == exerciseID }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(exercise.title)
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

                        Text("Énoncé")
                            .font(.headline)
                        KaTeXView(content: exercise.statement, mode: .preview, fontSize: 18, minHeight: 80)
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(8)

                        if !exercise.expectedAnswer.isEmpty {
                            Text("Réponse attendue")
                                .font(.headline)
                            KaTeXView(
                                content: "$\(exercise.expectedAnswer)$",
                                mode: .preview,
                                fontSize: 16,
                                minHeight: 40
                            )
                        }

                        if let imageURL = exercise.statementImageURL {
                            Text("Image source")
                                .font(.headline)
                            AsyncImageFromStorage(path: imageURL)
                        }

                        HStack {
                            Button {
                                windowManager.openEditExerciseWindow(exercise: exercise, viewModel: viewModel)
                            } label: {
                                Label("Modifier", systemImage: "pencil")
                            }
                            .buttonStyle(.bordered)
                        }

                        Spacer()
                    }
                    .padding()
                }
                .id(exerciseID)
            } else {
                Text("Sélectionnez un exercice pour voir les détails")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    windowManager.openAddExerciseWindow(with: viewModel)
                } label: {
                    Label("Ajouter un exercice", systemImage: "plus")
                }
            }
        }
        .alert("Supprimer l'exercice", isPresented: $showingDeleteAlert) {
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                if let exercise = exerciseToDelete, let id = exercise.id {
                    Task {
                        try? await viewModel.deleteExercise(id: id)
                    }
                }
            }
        } message: {
            Text("Êtes-vous sûr de vouloir supprimer cet exercice ?")
        }
    }
}
