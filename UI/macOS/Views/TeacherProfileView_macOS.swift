//
//  TeacherProfileView_macOS.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 19.03.2026.
//

import SwiftUI

/// Teacher profile view for macOS.
/// Displays and allows editing of the teacher's name.
struct TeacherProfileView_macOS: View {
    @StateObject private var viewModel = TeacherProfileViewModel()
    @ObservedObject private var localization = LocalizationManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var showDeleteConfirmation: Bool = false
    @State private var showResetDemoConfirmation: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                Form {
                    Section("Informations personnelles".tr) {
                        LabeledContent("Email") {
                            Text(viewModel.email)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }

                        TextField("Prénom".tr, text: $viewModel.firstName)
                            .textContentType(.givenName)

                        TextField("Nom".tr, text: $viewModel.lastName)
                            .textContentType(.familyName)
                    }

                    Section("Compte".tr) {
                        LabeledContent("Membre depuis".tr) {
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

                        Text("La démo crée une classe fictive avec dix élèves, trente exercices et un devoir actif. Pour essayer côté élève, saisissez le code de cette classe sur un iPad. La réinitialisation efface uniquement les données de démo ; les exercices de démo utilisés dans vos devoirs sont conservés.".tr)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } header: {
                        Text("Données de démo".tr)
                    }

                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Supprimer mon compte".tr, systemImage: "person.crop.circle.badge.xmark")
                        }
                        .disabled(viewModel.isDeletingAccount)

                        Text("Supprime définitivement votre compte, vos classes, le travail de vos élèves et vos exercices.".tr)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } header: {
                        Text("Compte".tr)
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
                .formStyle(.grouped)
            }

            Divider()

            HStack {
                Button("Annuler".tr) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    Task { await viewModel.save() }
                } label: {
                    if viewModel.isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Enregistrer".tr)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isLoading || viewModel.isSaving)
            }
            .padding()
        }
        .frame(width: 480, height: 600)
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
