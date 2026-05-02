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

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Informations de l'élève")) {
                    TextField("Prénom", text: $firstName)
                    TextField("Nom", text: $lastName)
                }
            }
            .navigationTitle("Ajouter Élève")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        Task {
                            try? await viewModel.addStudent(
                                firstName: firstName,
                                lastName: lastName,
                                classID: classID
                            )
                            dismiss()
                        }
                    }
                    .disabled(firstName.isEmpty || lastName.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }
}
