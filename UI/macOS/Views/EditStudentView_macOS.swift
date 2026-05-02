//
//  EditStudentView_macOS.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.11.2024.
//

import SwiftUI

/// Sheet for editing a student's name.
struct EditStudentView_macOS: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: TeacherViewModel
    let student: Student

    @State private var firstName: String
    @State private var lastName: String
    @State private var showError = false
    @State private var errorMessage = ""

    init(viewModel: TeacherViewModel, student: Student) {
        self.viewModel = viewModel
        self.student = student
        _firstName = State(initialValue: student.firstName)
        _lastName = State(initialValue: student.lastName)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Modifier l'élève")
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

                Button("Enregistrer") {
                    var updated = student
                    updated.firstName = firstName
                    updated.lastName = lastName
                    Task {
                        do {
                            try await viewModel.updateStudent(updated)
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
