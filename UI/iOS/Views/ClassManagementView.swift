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

    @State private var classToDelete: ClassRoom?

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
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        classToDelete = classRoom
                    } label: {
                        Label("Supprimer".tr, systemImage: "trash")
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
        .alert(
            "Supprimer la classe ?".tr,
            isPresented: Binding(get: { classToDelete != nil }, set: { if !$0 { classToDelete = nil } })
        ) {
            Button("Annuler".tr, role: .cancel) { classToDelete = nil }
            Button("Supprimer".tr, role: .destructive) {
                if let id = classToDelete?.id {
                    Task { try? await viewModel.deleteClass(id: id) }
                }
                classToDelete = nil
            }
        } message: {
            Text("La classe, ses élèves, leurs copies et leurs dessins seront définitivement supprimés.".tr)
        }
    }

    @ViewBuilder
    private func classDetailView(_ classRoom: ClassRoom) -> some View {
        if let _ = classRoom.id {
            ClassDetailView_iOS(classRoom: classRoom, viewModel: viewModel)
        }
    }
}

/// Sub-view so we can keep state (notationStrict toggle, save status) for
/// the currently-shown class without polluting the parent List.
private struct ClassDetailView_iOS: View {
    let classRoom: ClassRoom
    @ObservedObject var viewModel: TeacherViewModel

    @State private var notationStrict: Bool
    @State private var showingAddStudent: Bool = false
    @State private var studentToDelete: Student?
    @State private var isSaving: Bool = false
    @State private var saveError: String?

    init(classRoom: ClassRoom, viewModel: TeacherViewModel) {
        self.classRoom = classRoom
        self.viewModel = viewModel
        self._notationStrict = State(initialValue: classRoom.isNotationStrict)
    }

    var body: some View {
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
                    // QR code to show the class, e.g. on the projector.
                    if let data = ClassCodeService.generateQRCode(from: classRoom.classCode),
                       let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 160, height: 160)
                            .frame(maxWidth: .infinity)
                    }
                }

                Section {
                    Toggle("Notation stricte".tr, isOn: $notationStrict)
                        .onChange(of: notationStrict) { _, newValue in
                            saveNotationStrict(newValue)
                        }
                    Text("L'IA signale les problèmes de notation séparément, sans pénaliser le fond.".tr)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let saveError {
                        Text(saveError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("Réglages de la classe".tr)
                }

                Section(header: Text("Élèves (\(viewModel.studentsInClass(classID).count))")) {
                    ForEach(viewModel.studentsInClass(classID)) { student in
                        StudentRow(student: student)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    studentToDelete = student
                                } label: {
                                    Label("Supprimer".tr, systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .navigationTitle(classRoom.name)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddStudent = true
                    } label: {
                        Label("Ajouter un élève".tr, systemImage: "person.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddStudent) {
                AddStudentView(viewModel: viewModel, classID: classID)
            }
            .alert(
                "Supprimer l'élève ?".tr,
                isPresented: Binding(get: { studentToDelete != nil }, set: { if !$0 { studentToDelete = nil } })
            ) {
                Button("Annuler".tr, role: .cancel) { studentToDelete = nil }
                Button("Supprimer".tr, role: .destructive) {
                    if let id = studentToDelete?.id {
                        Task { try? await viewModel.deleteStudent(id: id, classID: classID) }
                    }
                    studentToDelete = nil
                }
            } message: {
                Text("L'élève, ses copies et ses dessins seront définitivement supprimés.".tr)
            }
            .onAppear {
                viewModel.selectClass(classID)
            }
        }
    }

    private func saveNotationStrict(_ newValue: Bool) {
        var updated = classRoom
        updated.notationStrict = newValue
        isSaving = true
        saveError = nil
        Task {
            do {
                try await viewModel.updateClass(updated)
            } catch {
                saveError = error.localizedDescription
                // Roll the toggle back so the UI matches the persisted state.
                notationStrict = classRoom.isNotationStrict
            }
            isSaving = false
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
                        InlineHint("Collez votre liste : un élève par ligne. Les en-têtes et séparateurs sont détectés automatiquement.", icon: "doc.on.clipboard")

                    case .manual:
                        TextEditor(text: $studentsText)
                            .frame(height: 180)
                        InlineHint("Un élève par ligne au format « Prénom Nom ».", icon: "text.alignleft")

                    case .csv:
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Importer un CSV".tr, systemImage: "doc.badge.arrow.up")
                        }
                        if studentsText.isEmpty {
                            InlineHint("Aucun fichier importé.", icon: "doc")
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
