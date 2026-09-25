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
    @State private var showDeleteConfirmation: Bool = false
    @State private var showResetDemoConfirmation: Bool = false


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
                        Picker(selection: Binding(
                            get: { localization.language },
                            set: { newLanguage in
                                localization.reopenProfileAfterRebuild = true
                                localization.language = newLanguage
                            }
                        )) {
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
                            Task { await viewModel.loadDemo() }
                        } label: {
                            Label("Charger les données de démo".tr, systemImage: "tray.and.arrow.down")
                        }
                        .disabled(viewModel.isWorkingOnDemo)

                        Button(role: .destructive) {
                            showResetDemoConfirmation = true
                        } label: {
                            Label("Réinitialiser la démo".tr, systemImage: "arrow.counterclockwise.circle")
                        }
                        .disabled(viewModel.isWorkingOnDemo)

                        if let demoMessage = viewModel.demoMessage {
                            Label(demoMessage.tr, systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    } header: {
                        Text("Données de démo".tr)
                    } footer: {
                        Text("La démo crée une classe fictive avec dix élèves, trente exercices et un devoir actif. Pour essayer côté élève, saisissez le code de cette classe sur un iPad. La réinitialisation efface uniquement les données de démo ; les exercices de démo utilisés dans vos devoirs sont conservés.".tr)
                    }

                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            if viewModel.isDeletingAccount {
                                ProgressView()
                            } else {
                                Text("Supprimer mon compte".tr)
                            }
                        }
                        .disabled(viewModel.isDeletingAccount)
                    } footer: {
                        Text("Supprime définitivement votre compte, vos classes, le travail de vos élèves et vos exercices.".tr)
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
                isPresented: $showResetDemoConfirmation,
                titleVisibility: .visible
            ) {
                Button("Réinitialiser".tr, role: .destructive) {
                    Task { await viewModel.resetDemo() }
                }
                Button("Annuler".tr, role: .cancel) {}
            } message: {
                Text("La classe de démo et le travail de ses élèves seront supprimés.".tr)
            }
            .confirmationDialog(
                "Supprimer votre compte ?".tr,
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Supprimer définitivement".tr, role: .destructive) {
                    Task { await viewModel.deleteAccount() }
                }
                Button("Annuler".tr, role: .cancel) {}
            } message: {
                Text("Cette action est irréversible.".tr)
            }
        }
    }
}
