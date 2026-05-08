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
    @State private var notationStrict: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Modifier la classe".tr)
                .font(.title)

            Form {
                Section(header: Text("Informations de la classe".tr)) {
                    TextField("Nom de la classe".tr, text: $newName)
                }

                Section(header: Text("Réglages de la classe".tr)) {
                    Toggle(isOn: $notationStrict) {
                        VStack(alignment: .leading) {
                            Text("Notation stricte".tr)
                            Text("L'IA signale les problèmes de notation séparément, sans pénaliser le fond.".tr)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear {
                newName = classRoom.name
                notationStrict = classRoom.isNotationStrict
            }

            HStack {
                Button("Annuler".tr) {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Sauvegarder".tr) {
                    var updated = classRoom
                    updated.name = newName
                    updated.notationStrict = notationStrict
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
        .frame(width: 480, height: 320)
    }
}
