//
//  TeacherView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.11.2024.
//

import SwiftUI

/// Teacher dashboard for iPad.
/// Tabs: Classes, Exercices, Devoirs, Soumissions, En direct, Statistiques.
struct TeacherView: View {
    @StateObject private var viewModel = TeacherViewModel()
    @State private var selectedTab = 0
    @State private var showingProfile = false

    var body: some View {
        // Each tab owns its NavigationStack. A NavigationView around the
        // TabView (as before) renders as a split view on iPad and drops the
        // tabs' titles and toolbar items, so the "+" buttons never showed.
        TabView(selection: $selectedTab) {
            NavigationStack {
                ClassManagementView(viewModel: viewModel)
                    .navigationTitle("Classes".tr)
                    .toolbar { accountMenu }
            }
            .tabItem {
                Label("Classes".tr, systemImage: "person.3")
            }
            .tag(0)

            NavigationStack {
                ExercisesListView(viewModel: viewModel)
                    .navigationTitle("Exercices".tr)
                    .toolbar { accountMenu }
            }
            .tabItem {
                Label("Exercices".tr, systemImage: "book")
            }
            .tag(1)

            NavigationStack {
                AssignmentListView_iOS(viewModel: viewModel)
                    .navigationTitle("Devoirs".tr)
                    .toolbar { accountMenu }
            }
            .tabItem {
                Label("Devoirs".tr, systemImage: "tray.full")
            }
            .tag(2)

            NavigationStack {
                SubmissionInboxView_iOS(viewModel: viewModel)
                    .navigationTitle("Soumissions".tr)
                    .toolbar { accountMenu }
            }
            .tabItem {
                Label("Soumissions".tr, systemImage: "tray.and.arrow.down")
            }
            .tag(3)

            NavigationStack {
                LiveDashboardView_iOS(viewModel: viewModel)
                    .navigationTitle("En direct".tr)
                    .toolbar { accountMenu }
            }
            .tabItem {
                Label("En direct".tr, systemImage: "dot.radiowaves.left.and.right")
            }
            .tag(4)

            NavigationStack {
                StatisticsView(viewModel: viewModel)
                    .navigationTitle("Statistiques".tr)
                    .toolbar { accountMenu }
            }
            .tabItem {
                Label("Statistiques".tr, systemImage: "chart.bar")
            }
            .tag(5)
        }
        .sheet(isPresented: $showingProfile) {
            TeacherProfileView()
        }
        .onAppear {
            if LocalizationManager.shared.reopenProfileAfterRebuild {
                LocalizationManager.shared.reopenProfileAfterRebuild = false
                showingProfile = true
            }
            if let teacherID = AuthenticationService.shared.currentUser?.uid {
                viewModel.startListening(teacherID: teacherID)
            }
        }
        .onDisappear {
            viewModel.stopListening()
        }
    }

    @ToolbarContentBuilder
    private var accountMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                if let email = AuthenticationService.shared.currentUser?.email {
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
                    try? AuthenticationService.shared.signOut()
                }
            } label: {
                Image(systemName: "person.circle")
            }
            .accessibilityLabel("Compte".tr)
        }
    }
}
