//
//  TeacherProfileView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 19.03.2026.
//

import SwiftUI

/// Teacher profile view for iPad.
/// Displays and allows editing of the teacher's name.
struct TeacherProfileView: View {
    @StateObject private var viewModel = TeacherProfileViewModel()
    @ObservedObject private var localization = LocalizationManager.shared
    @Environment(\.dismiss) var dismiss

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
        }
    }
}
