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
                    Section("Informations personnelles") {
                        HStack {
                            Text("Email")
                            Spacer()
                            Text(viewModel.email)
                                .foregroundColor(.secondary)
                        }

                        TextField("Prénom", text: $viewModel.firstName)
                            .textContentType(.givenName)

                        TextField("Nom", text: $viewModel.lastName)
                            .textContentType(.familyName)
                    }

                    Section("Compte") {
                        HStack {
                            Text("Membre depuis")
                            Spacer()
                            Text(viewModel.createdAt.formatted(date: .long, time: .omitted))
                                .foregroundColor(.secondary)
                        }
                    }

                    if let error = viewModel.error {
                        Section {
                            Text(error)
                                .foregroundColor(.red)
                        }
                    }

                    if viewModel.saveSuccess {
                        Section {
                            Label("Profil mis à jour", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .navigationTitle("Mon profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.save() }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                        } else {
                            Text("Enregistrer").bold()
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
