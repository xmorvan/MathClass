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
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                Form {
                    Section("Informations personnelles") {
                        LabeledContent("Email") {
                            Text(viewModel.email)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }

                        TextField("Prénom", text: $viewModel.firstName)
                            .textContentType(.givenName)

                        TextField("Nom", text: $viewModel.lastName)
                            .textContentType(.familyName)
                    }

                    Section("Compte") {
                        LabeledContent("Membre depuis") {
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
                .formStyle(.grouped)
            }

            Divider()

            HStack {
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    Task { await viewModel.save() }
                } label: {
                    if viewModel.isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Enregistrer")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isLoading || viewModel.isSaving)
            }
            .padding()
        }
        .frame(width: 450, height: 350)
        .task {
            await viewModel.load()
        }
    }
}
