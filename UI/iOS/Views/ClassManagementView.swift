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
                Section(header: Text("Informations")) {
                    HStack {
                        Text("Code classe")
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

/// Sheet for creating a class on iPad.
struct AddClassView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: TeacherViewModel
    @State private var className = ""
    @State private var studentsText = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Informations de la classe")) {
                    TextField("Nom de la classe", text: $className)
                }

                Section(header: Text("Liste des élèves")) {
                    TextEditor(text: $studentsText)
                        .frame(height: 200)
                    Text("Collez votre liste : un élève par ligne. Les en-têtes et séparateurs sont détectés automatiquement.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Nouvelle Classe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
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
            .alert("Erreur", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
}
