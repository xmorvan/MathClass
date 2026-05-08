//
//  ClassManagementView_macOS.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.11.2024.
//

import SwiftUI

/// Master-detail view for teacher class management on macOS.
/// Left panel: list of ClassRoom objects. Right panel: detail of selected class.
struct ClassManagementView_macOS: View {
    @ObservedObject var viewModel: TeacherViewModel
    @State private var showingAddClass = false
    @State private var showingDeleteConfirmation = false

    @State private var classToEdit: ClassRoom?
    @State private var classToDelete: ClassRoom?
    @State private var selectedClassID: String?

    var body: some View {
        HSplitView {
            // MARK: - Class List
            VStack {
                List(viewModel.classes, selection: $selectedClassID) { classRoom in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(classRoom.name)
                                .font(.headline)
                            Text("Code: \(classRoom.classCode)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            classToEdit = classRoom
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(BorderlessButtonStyle())

                        Button {
                            classToDelete = classRoom
                            showingDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .tag(classRoom.id)
                }
                .frame(minWidth: 220)

                Button("Nouvelle classe".tr) {
                    showingAddClass = true
                }
                .padding()
            }

            // MARK: - Detail
            if let classID = selectedClassID,
               let classRoom = viewModel.classes.first(where: { $0.id == classID }) {
                ClassDetailView_macOS(viewModel: viewModel, classRoom: classRoom)
                    .id(classID)
            } else {
                Text("Sélectionnez une classe".tr)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .onChange(of: selectedClassID) { _, newID in
            if let newID = newID {
                viewModel.selectClass(newID)
            }
        }
        .sheet(isPresented: $showingAddClass) {
            AddClassView_macOS(viewModel: viewModel)
        }
        .sheet(item: $classToEdit) { classRoom in
            EditClassView_macOS(viewModel: viewModel, classRoom: classRoom)
        }
        .alert("Supprimer la classe".tr, isPresented: $showingDeleteConfirmation) {
            Button("Annuler".tr, role: .cancel) { }
            Button("Supprimer".tr, role: .destructive) {
                if let classRoom = classToDelete, let id = classRoom.id {
                    Task {
                        try? await viewModel.deleteClass(id: id)
                    }
                }
            }
        } message: {
            Text("Êtes-vous sûr de vouloir supprimer cette classe et tous ses élèves ?".tr)
        }
    }
}
