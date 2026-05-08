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
                    .navigationTitle("Classes".tr)
                    .tabItem {
                        Label("Classes".tr, systemImage: "person.3")
                    }
                    .tag(0)

                ExercisesListView(viewModel: viewModel)
                    .navigationTitle("Exercices".tr)
                    .tabItem {
                        Label("Exercices".tr, systemImage: "book")
                    }
                    .tag(1)

                AssignmentListView_iOS(viewModel: viewModel)
                    .navigationTitle("Devoirs".tr)
                    .tabItem {
                        Label("Devoirs".tr, systemImage: "tray.full")
                    }
                    .tag(2)

                SubmissionInboxView_iOS(viewModel: viewModel)
                    .navigationTitle("Soumissions".tr)
                    .tabItem {
                        Label("Soumissions".tr, systemImage: "tray.and.arrow.down")
                    }
                    .tag(3)

                LiveDashboardView_iOS(viewModel: viewModel)
                    .navigationTitle("En direct".tr)
                    .tabItem {
                        Label("En direct".tr, systemImage: "dot.radiowaves.left.and.right")
                    }
                    .tag(4)

                StatisticsView(viewModel: viewModel)
                    .navigationTitle("Statistiques".tr)
                    .tabItem {
                        Label("Statistiques".tr, systemImage: "chart.bar")
                    }
                    .tag(5)
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
                            Label("Mon profil".tr, systemImage: "person.text.rectangle")
                        }
                        Divider()
                        Button("Déconnexion".tr, role: .destructive) {
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
