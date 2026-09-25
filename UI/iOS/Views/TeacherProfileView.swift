//
//  TeacherProfileView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 19.03.2026.
//

import SwiftUI

/// Teacher profile view for iPad.
/// Displays and allows editing of the teacher's name, plus the demo seed
/// load / reset entry points the salesperson uses on a fresh iPad.
struct TeacherProfileView: View {
    @StateObject private var viewModel = TeacherProfileViewModel()
    @ObservedObject private var localization = LocalizationManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var showResetConfirm: Bool = false
    @State private var demoStatus: String?

    var body: some View {
        NavigationView {
            Form {
                if viewModel.isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                } else {
                    Section("Informations personnelles".tr) {
                        HStack {
                            Text("Email".tr)
                            Spacer()
                            Text(viewModel.email)
                                .foregroundColor(.secondary)
                        }

                        TextField("Prénom".tr, text: $viewModel.firstName)
                            .textContentType(.givenName)

                        TextField("Nom".tr, text: $viewModel.lastName)
                            .textContentType(.familyName)
                    }

                    Section("Compte".tr) {
                        HStack {
                            Text("Membre depuis".tr)
                            Spacer()
                            Text(viewModel.createdAt.formatted(date: .long, time: .omitted))
                                .foregroundColor(.secondary)
                        }
                    }

                    Section {
                        Picker(selection: $localization.language) {
                            ForEach(AppLanguage.allCases, id: \.self) { lang in
                                Text("\(lang.flag) \(lang.displayName)").tag(lang)
                            }
                        } label: {
                            Text("Langue".tr)
                        }
                        .pickerStyle(.menu)

                        Text("Choisissez la langue de l'application. Le changement est immédiat.".tr)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } header: {
                        Text("Préférence linguistique".tr)
                    }

                    Section {
                        Button {
                            Task { await runDemoSeed() }
                        } label: {
                            Label("Charger les données de démo".tr, systemImage: "tray.and.arrow.down")
                        }

                        Button(role: .destructive) {
                            showResetConfirm = true
                        } label: {
                            Label("Réinitialiser la démo".tr, systemImage: "arrow.counterclockwise.circle")
                        }

                        Text("La démo crée une classe et un groupe d'exercices fictifs. La réinitialisation efface uniquement les données de démo, pas vos vraies classes.".tr)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if let demoStatus {
                            Text(demoStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("Données de démo".tr)
                    }

                    if let error = viewModel.error {
                        Section {
                            Text(error)
                                .foregroundColor(.red)
                        }
                    }

                    if viewModel.saveSuccess {
                        Section {
                            Label("Profil mis à jour".tr, systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .navigationTitle("Mon profil".tr)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer".tr) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.save() }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                        } else {
                            Text("Enregistrer".tr).bold()
                        }
                    }
                    .disabled(viewModel.isLoading || viewModel.isSaving)
                }
            }
            .task {
                await viewModel.load()
            }
            .confirmationDialog(
                "Réinitialiser la démo ?".tr,
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Réinitialiser".tr, role: .destructive) {
                    Task { await runDemoReset() }
                }
                Button("Annuler".tr, role: .cancel) {}
            } message: {
                Text("La réinitialisation efface uniquement les données de démo, pas vos vraies classes.".tr)
            }
        }
    }

    private func runDemoSeed() async {
        guard let teacherID = AuthenticationService.shared.currentUser?.uid else { return }
        do {
            try await DemoSeedService.shared.seed(teacherID: teacherID)
            demoStatus = "Données de démo chargées.".tr
        } catch {
            viewModel.error = "Démo: \(error.localizedDescription)"
        }
    }

    private func runDemoReset() async {
        do {
            try await DemoSeedService.shared.reset()
            demoStatus = "Démo réinitialisée.".tr
        } catch {
            viewModel.error = "Reset démo: \(error.localizedDescription)"
        }
    }
}
