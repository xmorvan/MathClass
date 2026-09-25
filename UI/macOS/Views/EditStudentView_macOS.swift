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
    @State private var level: Int
    @State private var showError = false
    @State private var errorMessage = ""

    init(viewModel: TeacherViewModel, student: Student) {
        self.viewModel = viewModel
        self.student = student
        _firstName = State(initialValue: student.firstName)
        _lastName = State(initialValue: student.lastName)
        // Clamp legacy docs that pre-date the level field to the default 3.
        _level = State(initialValue: student.clampedLevel ?? 3)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Modifier l'élève".tr)
                .font(.title)

            Form {
                TextField("Prénom".tr, text: $firstName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                TextField("Nom".tr, text: $lastName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Picker("Niveau".tr, selection: $level) {
                    ForEach(1...5, id: \.self) { lvl in
                        Text(LocalizationManager.shared.format("Niveau %@", String(lvl))).tag(lvl)
                    }
                }
                .pickerStyle(.segmented)
                InlineHint("Changer le niveau ne pénalise pas l'élève : sa progression continue depuis sa dernière étape.", icon: "info.circle")
            }

            HStack {
                Button("Annuler".tr) {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Enregistrer".tr) {
                    var updated = student
                    updated.firstName = firstName
                    updated.lastName = lastName
                    updated.level = level
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
        .frame(width: 480, height: 280)
        .alert("Erreur".tr, isPresented: $showError) {
            Button("OK".tr, role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
}
