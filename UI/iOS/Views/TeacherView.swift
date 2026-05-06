//
//  TeacherView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.11.2024.
//

import SwiftUI

/// Teacher dashboard for iPad.
/// Tabs: Classes, Exercices, Devoirs, Statistiques.
struct TeacherView: View {
    @StateObject private var viewModel = TeacherViewModel()
    @State private var selectedTab = 0
    @State private var showingProfile = false

    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                ClassManagementView(viewModel: viewModel)
                    .navigationTitle("Classes")
                    .tabItem {
                        Label("Classes", systemImage: "person.3")
                    }
                    .tag(0)

                ExercisesListView(viewModel: viewModel)
                    .navigationTitle("Exercices")
                    .tabItem {
                        Label("Exercices", systemImage: "book")
                    }
                    .tag(1)

                AssignmentListView_iOS(viewModel: viewModel)
                    .navigationTitle("Devoirs")
                    .tabItem {
                        Label("Devoirs", systemImage: "tray.full")
                    }
                    .tag(2)

                SubmissionInboxView_iOS(viewModel: viewModel)
                    .navigationTitle("Soumissions")
                    .tabItem {
                        Label("Soumissions", systemImage: "tray.and.arrow.down")
                    }
                    .tag(3)

                StatisticsView(viewModel: viewModel)
                    .navigationTitle("Statistiques")
                    .tabItem {
                        Label("Statistiques", systemImage: "chart.bar")
                    }
                    .tag(4)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if let email = AuthenticationService.shared.currentUser?.email {
                            Text("Connecté : \(email)")
                            Divider()
                        }
                        Button {
                            showingProfile = true
                        } label: {
                            Label("Mon profil", systemImage: "person.text.rectangle")
                        }
                        Divider()
                        Button("Déconnexion", role: .destructive) {
                            try? AuthenticationService.shared.signOut()
                        }
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingProfile) {
            TeacherProfileView()
        }
        .onAppear {
            if let teacherID = AuthenticationService.shared.currentUser?.uid {
                viewModel.startListening(teacherID: teacherID)
            }
        }
        .onDisappear {
            viewModel.stopListening()
        }
    }
}
