//
//  ClassStudentsView_macOS.swift
//  MathClass
//
//  Created by Xavier Morvan on 04.02.2025.
//

import SwiftUI

/// Reusable student list for a class. Used within ClassDetailView_macOS.
struct ClassStudentsView_macOS: View {
    @ObservedObject var viewModel: TeacherViewModel
    let classID: String

    @State private var showingEditStudent = false
    @State private var showingDeleteConfirmation = false
    @State private var studentToEdit: Student?
    @State private var studentToDelete: Student?

    var body: some View {
        VStack {
            List {
                ForEach(viewModel.studentsInClass(classID)) { student in
                    HStack {
                        Text(student.fullName)
                        Spacer()
                        Button("Éditer") {
                            studentToEdit = student
                            showingEditStudent = true
                        }
                        .buttonStyle(BorderlessButtonStyle())

                        Button {
                            studentToDelete = student
                            showingDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
            }
            .listStyle(PlainListStyle())
        }
        .sheet(isPresented: $showingEditStudent) {
            if let student = studentToEdit {
                EditStudentView_macOS(viewModel: viewModel, student: student)
            }
        }
        .alert("Supprimer l'élève", isPresented: $showingDeleteConfirmation) {
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                if let student = studentToDelete,
                   let studentID = student.id {
                    Task {
                        try? await viewModel.deleteStudent(id: studentID, classID: classID)
                    }
                }
            }
        } message: {
            Text("Êtes-vous sûr de vouloir supprimer cet élève ?")
        }
    }
}
