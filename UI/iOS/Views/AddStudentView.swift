//
//  AddStudentView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.11.2024.
//

import SwiftUI

/// Sheet for adding a student on iPad.
struct AddStudentView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: TeacherViewModel
    let classID: String

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var level: Int = 3

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Informations de l'élève".tr)) {
                    TextField("Prénom".tr, text: $firstName)
                    TextField("Nom".tr, text: $lastName)
                    InlineHint("Le nom apparaîtra sur la liste de la classe et sur les rapports.", icon: "person")
                }

                Section {
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { value in
                            Button {
                                level = value
                            } label: {
                                Image(systemName: value <= level ? "star.fill" : "star")
                                    .foregroundColor(value <= level ? .yellow : .gray)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        Text(LocalizationManager.shared.format("Niveau %@", String(level)))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    InlineHint("Le niveau guide la différenciation : exercices et progression sont adaptés au niveau initial.", icon: "info.circle")
                } header: {
                    Text("Niveau initial (1–5)".tr)
                }
            }
            .navigationTitle("Ajouter Élève".tr)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter".tr) {
                        Task {
                            try? await viewModel.addStudent(
                                firstName: firstName,
                                lastName: lastName,
                                classID: classID,
                                level: level
                            )
                            dismiss()
                        }
                    }
                    .disabled(firstName.isEmpty || lastName.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler".tr) { dismiss() }
                }
            }
        }
    }
}
