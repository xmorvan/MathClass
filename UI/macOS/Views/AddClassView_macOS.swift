//
//  AddClassView_macOS.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.11.2024.
//

import SwiftUI

/// Sheet for creating a new class with student import.
/// Supports three import methods: manual entry, paste from clipboard, CSV file.
struct AddClassView_macOS: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: TeacherViewModel
    @State private var className = ""
    @State private var studentsText = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var importMethod: ImportMethod = .paste

    enum ImportMethod: String, CaseIterable {
        case paste = "Coller"
        case manual = "Manuel"
        case csv = "Fichier CSV"
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Nouvelle Classe")
                .font(.title)
                .padding(.top)

            // Class name
            TextField("Nom de la classe", text: $className)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            // Import method picker
            Picker("Méthode d'import", selection: $importMethod) {
                ForEach(ImportMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)

            // Student import area
            VStack(alignment: .leading, spacing: 8) {
                Text("Liste des élèves")
                    .font(.headline)

                switch importMethod {
                case .paste, .manual:
                    TextEditor(text: $studentsText)
                        .font(.body)
                        .frame(height: 200)
                        .border(Color.gray.opacity(0.2))

                    if importMethod == .paste {
                        Text("Collez votre liste. Détection automatique : tabulations, points-virgules, virgules ou espaces. Les en-têtes français (nom, prénom) sont reconnus.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Un élève par ligne au format « Prénom Nom »")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                case .csv:
                    Button("Choisir un fichier CSV...") {
                        importCSVFile()
                    }
                    .padding()

                    if !studentsText.isEmpty {
                        Text("Aperçu:")
                            .font(.caption).bold()
                        TextEditor(text: .constant(studentsText))
                            .font(.caption)
                            .frame(height: 150)
                            .border(Color.gray.opacity(0.2))
                            .disabled(true)
                    }
                }
            }
            .padding(.horizontal)

            // Buttons
            HStack {
                Button("Annuler") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Créer la classe") {
                    Task {
                        do {
                            try await viewModel.addClass(name: className, studentsText: studentsText)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }
                .keyboardShortcut(.return)
                .disabled(className.isEmpty || studentsText.isEmpty)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .alert("Erreur", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - CSV File Import

    private func importCSVFile() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Sélectionnez un fichier CSV contenant la liste des élèves"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let content = try String(contentsOf: url, encoding: .utf8)
                    DispatchQueue.main.async {
                        self.studentsText = content
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.errorMessage = "Impossible de lire le fichier: \(error.localizedDescription)"
                        self.showError = true
                    }
                }
            }
        }
        #endif
    }
}
