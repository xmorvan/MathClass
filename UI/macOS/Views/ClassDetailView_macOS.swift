//
//  ClassDetailView_macOS.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.11.2024.
//

import SwiftUI

/// Detail view for a selected class. Shows class code, students, and chapters.
struct ClassDetailView_macOS: View {
    @ObservedObject var viewModel: TeacherViewModel
    let classRoom: ClassRoom

    @State private var showingAddStudent = false
    @State private var showingEditStudent = false
    @State private var showingDeleteConfirmation = false
    @State private var studentToEdit: Student?
    @State private var studentToDelete: Student?

    // Chapter management
    @State private var showingAddChapter = false
    @State private var newChapterName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                classHeader
                Divider()
                studentsSection
                Divider()
                chaptersSection
            }
            .padding()
        }
        .sheet(isPresented: $showingAddStudent) {
            if let classID = classRoom.id {
                AddStudentView_macOS(viewModel: viewModel, classID: classID)
            }
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
                   let studentID = student.id,
                   let classID = classRoom.id {
                    Task {
                        try? await viewModel.deleteStudent(id: studentID, classID: classID)
                    }
                }
            }
        } message: {
            Text("Êtes-vous sûr de vouloir supprimer cet élève ?")
        }
    }

    // MARK: - Class Header

    private var classHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(classRoom.name)
                    .font(.title)
                    .bold()

                HStack {
                    Text("Code classe:")
                        .foregroundColor(.secondary)
                    Text(classRoom.classCode)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .textSelection(.enabled)
                }

                if let createdAt = classRoom.createdAt {
                    Text("Créée le \(createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()

            // QR code of the class code (for projecting)
            if let qrData = ClassCodeService.generateQRCode(from: classRoom.classCode),
               let qrImage = NSImage(data: qrData) {
                Image(nsImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 100, height: 100)
            }
        }
    }

    // MARK: - Students Section

    private var studentsSection: some View {
        // Filter to the students of THIS class — the previous version used
        // `viewModel.students` (every student the teacher has, across all
        // classes), so every class detail page showed the same list.
        let classStudents = viewModel.studentsInClass(classRoom.id ?? "")
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Élèves (\(classStudents.count))")
                    .font(.title2)
                    .bold()
                Spacer()
                Button {
                    showingAddStudent = true
                } label: {
                    Label("Ajouter", systemImage: "person.badge.plus")
                }
            }

            if classStudents.isEmpty {
                Text("Aucun élève dans cette classe.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                Table(classStudents) {
                    TableColumn("Prénom") { student in
                        Text(student.firstName)
                    }
                    TableColumn("Nom") { student in
                        Text(student.lastName)
                    }
                    TableColumn("Appareil lié") { student in
                        if student.deviceToken != nil {
                            Image(systemName: "ipad")
                                .foregroundColor(.green)
                        } else {
                            Text("—")
                                .foregroundColor(.secondary)
                        }
                    }
                    TableColumn("Actions") { student in
                        HStack(spacing: 8) {
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
                .frame(minHeight: 200)
            }
        }
    }

    // MARK: - Chapters Section

    private var chaptersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Chapitres (\(viewModel.chapters.count))")
                    .font(.title2)
                    .bold()
                Spacer()
                Button {
                    showingAddChapter = true
                } label: {
                    Label("Ajouter", systemImage: "plus")
                }
                .popover(isPresented: $showingAddChapter) {
                    VStack(spacing: 12) {
                        Text("Nouveau chapitre")
                            .font(.headline)
                        TextField("Nom du chapitre", text: $newChapterName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 250)
                        HStack {
                            Button("Annuler") {
                                newChapterName = ""
                                showingAddChapter = false
                            }
                            Spacer()
                            Button("Ajouter") {
                                if let classID = classRoom.id, !newChapterName.isEmpty {
                                    Task {
                                        try? await viewModel.addChapter(name: newChapterName, classID: classID)
                                        newChapterName = ""
                                        showingAddChapter = false
                                    }
                                }
                            }
                            .disabled(newChapterName.isEmpty)
                        }
                    }
                    .padding()
                }
            }

            if viewModel.chapters.isEmpty {
                Text("Aucun chapitre. Ajoutez des chapitres pour organiser les exercices.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(viewModel.chapters) { chapter in
                    ChapterRowView(chapter: chapter, viewModel: viewModel)
                }
            }
        }
    }
}

// MARK: - Chapter Row

struct ChapterRowView: View {
    let chapter: Chapter
    @ObservedObject var viewModel: TeacherViewModel

    @State private var showAddCompetency = false
    @State private var newCompetencyLabel = ""

    var competencies: [Competency] {
        viewModel.chapterRepo.competencies[chapter.id ?? ""] ?? []
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(chapter.name)
                        .font(.headline)
                    Spacer()
                    Button {
                        showAddCompetency.toggle()
                    } label: {
                        Label("Compétence", systemImage: "plus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(BorderlessButtonStyle())

                    Button {
                        if let id = chapter.id {
                            Task { try? await viewModel.deleteChapter(id: id) }
                        }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }

                if !competencies.isEmpty {
                    ForEach(competencies) { competency in
                        HStack {
                            Text("• \(competency.label)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button {
                                if let compID = competency.id, let chapterID = chapter.id {
                                    Task { try? await viewModel.deleteCompetency(id: compID, chapterID: chapterID) }
                                }
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .foregroundColor(.red)
                                    .font(.caption2)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                }

                if showAddCompetency {
                    HStack {
                        TextField("Libellé de la compétence", text: $newCompetencyLabel)
                            .textFieldStyle(.roundedBorder)
                        Button("OK") {
                            if let chapterID = chapter.id, !newCompetencyLabel.isEmpty {
                                Task {
                                    try? await viewModel.addCompetency(label: newCompetencyLabel, chapterID: chapterID)
                                    newCompetencyLabel = ""
                                    showAddCompetency = false
                                }
                            }
                        }
                        .disabled(newCompetencyLabel.isEmpty)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}
