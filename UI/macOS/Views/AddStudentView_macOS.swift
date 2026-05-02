//
//  AddStudentView_macOS.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 14.11.2024.
//

import SwiftUI

/// Sheet for adding a single student to a class.
struct AddStudentView_macOS: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: TeacherViewModel
    let classID: String

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Ajouter un élève")
                .font(.title)

            Form {
                TextField("Prénom", text: $firstName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                TextField("Nom", text: $lastName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            HStack {
                Button("Annuler") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Ajouter") {
                    Task {
                        do {
                            try await viewModel.addStudent(
                                firstName: firstName,
                                lastName: lastName,
                                classID: classID
                            )
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }
                .keyboardShortcut(.return)
                .disabled(firstName.isEmpty || lastName.isEmpty)
            }
        }
        .padding()
        .frame(width: 300, height: 200)
        .alert("Erreur", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
}
