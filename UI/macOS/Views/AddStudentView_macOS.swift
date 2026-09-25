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
    @State private var level: Int = 3
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Ajouter un élève".tr)
                .font(.title)

            Form {
                TextField("Prénom".tr, text: $firstName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                TextField("Nom".tr, text: $lastName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Picker("Niveau".tr, selection: $level) {
                    ForEach(1...5, id: \.self) { lvl in
                        Text("Niveau \(lvl)").tag(lvl)
                    }
                }
                .pickerStyle(.segmented)
                InlineHint("Le niveau guide la différenciation : exercices et progression sont adaptés au niveau initial.", icon: "info.circle")
            }

            HStack {
                Button("Annuler".tr) {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Ajouter".tr) {
                    Task {
                        do {
                            try await viewModel.addStudent(
                                firstName: firstName,
                                lastName: lastName,
                                classID: classID,
                                level: level
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
        .frame(width: 320, height: 240)
        .alert("Erreur".tr, isPresented: $showError) {
            Button("OK".tr, role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
}
