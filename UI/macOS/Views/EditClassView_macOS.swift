//
//  EditClassView_macOS.swift
//  MathClass
//
//  Created by Xavier Morvan on 04.02.2025.
//

import SwiftUI

/// Sheet for editing a ClassRoom's name.
struct EditClassView_macOS: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: TeacherViewModel
    @State var classRoom: ClassRoom
    @State private var newName: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Modifier la classe")
                .font(.title)

            TextField("Nom de la classe", text: $newName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onAppear {
                    newName = classRoom.name
                }

            HStack {
                Button("Annuler") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Sauvegarder") {
                    var updated = classRoom
                    updated.name = newName
                    Task {
                        try? await viewModel.updateClass(updated)
                        dismiss()
                    }
                }
                .keyboardShortcut(.return)
                .disabled(newName.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 200)
    }
}
