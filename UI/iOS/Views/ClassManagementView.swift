//
//  ClassManagementView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.11.2024.
//

import SwiftUI

/// Teacher's class management view for iPad.
struct ClassManagementView: View {
    @ObservedObject var viewModel: TeacherViewModel
    @State private var showingAddClass = false
    @State private var selectedClassID: String?

    var body: some View {
        List {
            ForEach(viewModel.classes) { classRoom in
                NavigationLink {
                    classDetailView(classRoom)
                } label: {
                    VStack(alignment: .leading) {
                        Text(classRoom.name)
                            .font(.headline)
                        Text("Code: \(classRoom.classCode)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddClass = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddClass) {
            AddClassView(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func classDetailView(_ classRoom: ClassRoom) -> some View {
        if let classID = classRoom.id {
            List {
                Section(header: Text("Informations".tr)) {
                    HStack {
                        Text("Code classe".tr)
                        Spacer()
                        Text(classRoom.classCode)
                            .foregroundColor(.blue)
                            .bold()
                    }
                }

                Section(header: Text("Élèves (\(viewModel.studentsInClass(classID).count))")) {
                    ForEach(viewModel.studentsInClass(classID)) { student in
                        StudentRow(student: student)
                    }
                }
            }
            .navigationTitle(classRoom.name)
            .onAppear {
                viewModel.selectClass(classID)
            }
        }
    }
}

/// Row displaying student name.
struct StudentRow: View {
    let student: Student

    var body: some View {
        HStack {
            Text(student.fullName)
            Spacer()
            if student.deviceToken != nil {
                Image(systemName: "ipad")
                    .foregroundColor(.green)
                    .font(.caption)
            }
        }
    }
}

/// Sheet for creating a class on iPad. Supports paste, manual entry,
/// and CSV file import via the standard system file picker.
struct AddClassView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: TeacherViewModel
    @State private var className = ""
    @State private var studentsText = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var importMethod: ImportMethod = .paste
    @State private var showFileImporter = false

    enum ImportMethod: String, CaseIterable, Identifiable {
        case paste
        case manual
        case csv

        var id: String { rawValue }
        var displayKey: String {
            switch self {
            case .paste: return "Coller"
            case .manual: return "Manuel"
            case .csv: return "Fichier CSV"
            }
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Informations de la classe".tr)) {
                    TextField("Nom de la classe".tr, text: $className)
                }

                Section(header: Text("Méthode d'import".tr)) {
                    Picker("", selection: $importMethod) {
                        ForEach(ImportMethod.allCases) { method in
                            Text(method.displayKey.tr).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Liste des élèves".tr)) {
                    switch importMethod {
                    case .paste:
                        TextEditor(text: $studentsText)
                            .frame(height: 180)
                        Text("Collez votre liste : un élève par ligne. Les en-têtes et séparateurs sont détectés automatiquement.".tr)
                            .font(.caption)
                            .foregroundColor(.secondary)

                    case .manual:
                        TextEditor(text: $studentsText)
                            .frame(height: 180)
                        Text("Un élève par ligne au format « Prénom Nom »".tr)
                            .font(.caption)
                            .foregroundColor(.secondary)

                    case .csv:
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Importer un CSV".tr, systemImage: "doc.badge.arrow.up")
                        }
                        if studentsText.isEmpty {
                            Text("Aucun fichier importé".tr)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            TextEditor(text: .constant(studentsText))
                                .frame(height: 140)
                                .disabled(true)
                        }
                    }
                }
            }
            .navigationTitle("Nouvelle Classe".tr)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler".tr) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer".tr) {
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
                    .disabled(className.isEmpty || studentsText.isEmpty)
                }
            }
            .alert("Erreur".tr, isPresented: $showError) {
                Button("OK".tr, role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText, .text],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let didStart = url.startAccessingSecurityScopedResource()
                    defer { if didStart { url.stopAccessingSecurityScopedResource() } }
                    do {
                        studentsText = try String(contentsOf: url, encoding: .utf8)
                    } catch {
                        errorMessage = String(format: "Échec du fichier : %@".tr, error.localizedDescription)
                        showError = true
                    }
                case .failure(let error):
                    errorMessage = String(format: "Échec du fichier : %@".tr, error.localizedDescription)
                    showError = true
                }
            }
        }
    }
}
