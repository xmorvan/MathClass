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
    @State private var showingDeleteConfirmation = false
    @State private var studentToEdit: Student?
    @State private var studentToDelete: Student?

    // Chapter management
    @State private var showingAddChapter = false
    @State private var newChapterName = ""

    @State private var newGroupName: String = ""
    @State private var showingAddGroup: Bool = false
    @State private var groupToDelete: StudentGroup?
    @State private var showingDeleteGroup: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                classHeader
                Divider()
                studentsSection
                Divider()
                groupsSection
                Divider()
                chaptersSection
            }
            .padding()
        }
        .onAppear {
            if let classID = classRoom.id {
                viewModel.startListeningToGroups(classID: classID)
            }
        }
        .sheet(isPresented: $showingAddStudent) {
            if let classID = classRoom.id {
                AddStudentView_macOS(viewModel: viewModel, classID: classID)
            }
        }
        .sheet(item: $studentToEdit) { student in
                EditStudentView_macOS(viewModel: viewModel, student: student)
        }
        .alert("Supprimer l'élève".tr, isPresented: $showingDeleteConfirmation) {
            Button("Annuler".tr, role: .cancel) { }
            Button("Supprimer".tr, role: .destructive) {
                if let student = studentToDelete,
                   let studentID = student.id,
                   let classID = classRoom.id {
                    Task {
                        try? await viewModel.deleteStudent(id: studentID, classID: classID)
                    }
                }
            }
        } message: {
            Text("Êtes-vous sûr de vouloir supprimer cet élève ?".tr)
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
                    Text("Code classe:".tr)
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
                    Label("Ajouter".tr, systemImage: "person.badge.plus")
                }
            }

            if classStudents.isEmpty {
                Text("Aucun élève dans cette classe.".tr)
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
                            Button("Éditer".tr) {
                                studentToEdit = student
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

    // MARK: - Groups Section

    private var groupsSection: some View {
        let classID = classRoom.id ?? ""
        let classStudents = viewModel.studentsInClass(classID)
        let groups = viewModel.groups
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Groupes".tr)
                    .font(.title2)
                    .bold()
                Spacer()
                Button {
                    showingAddGroup = true
                } label: {
                    Label("Ajouter un groupe".tr, systemImage: "person.3")
                }
                .popover(isPresented: $showingAddGroup) {
                    VStack(spacing: 12) {
                        Text("Ajouter un groupe".tr)
                            .font(.headline)
                        TextField("Nom du groupe (optionnel)".tr, text: $newGroupName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 250)
                        HStack {
                            Button("Annuler".tr) {
                                newGroupName = ""
                                showingAddGroup = false
                            }
                            Spacer()
                            Button("Ajouter".tr) {
                                guard !newGroupName.isEmpty, !classID.isEmpty else { return }
                                Task {
                                    try? await viewModel.createGroup(name: newGroupName, classID: classID)
                                    newGroupName = ""
                                    showingAddGroup = false
                                }
                            }
                            .disabled(newGroupName.isEmpty)
                        }
                    }
                    .padding()
                }
            }
            Text("Glissez les élèves vers un groupe pour les organiser.".tr)
                .font(.caption)
                .foregroundColor(.secondary)

            if groups.isEmpty {
                Text("Aucun groupe".tr)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(groups) { group in
                    GroupRowView_macOS(
                        group: group,
                        classID: classID,
                        students: classStudents,
                        viewModel: viewModel,
                        onDelete: {
                            groupToDelete = group
                            showingDeleteGroup = true
                        }
                    )
                }
            }
        }
        .alert("Supprimer le groupe".tr, isPresented: $showingDeleteGroup) {
            Button("Annuler".tr, role: .cancel) {}
            Button("Supprimer".tr, role: .destructive) {
                if let group = groupToDelete, let id = group.id {
                    Task {
                        try? await viewModel.deleteGroup(id: id, classID: classID)
                    }
                }
            }
        } message: {
            Text("Êtes-vous sûr de vouloir supprimer ce groupe ?".tr)
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
                    Label("Ajouter".tr, systemImage: "plus")
                }
                .popover(isPresented: $showingAddChapter) {
                    VStack(spacing: 12) {
                        Text("Nouveau chapitre".tr)
                            .font(.headline)
                        TextField("Nom du chapitre".tr, text: $newChapterName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 250)
                        HStack {
                            Button("Annuler".tr) {
                                newChapterName = ""
                                showingAddChapter = false
                            }
                            Spacer()
                            Button("Ajouter".tr) {
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
                Text("Aucun chapitre. Ajoutez des chapitres pour organiser les exercices.".tr)
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

// MARK: - Group Row (macOS)

struct GroupRowView_macOS: View {
    let group: StudentGroup
    let classID: String
    let students: [Student]
    @ObservedObject var viewModel: TeacherViewModel
    let onDelete: () -> Void

    @State private var isExpanded: Bool = false

    private var memberStudents: [Student] {
        students.filter { id in group.studentIDs.contains(id.id ?? "") }
    }

    private var nonMemberStudents: [Student] {
        students.filter { id in !group.studentIDs.contains(id.id ?? "") }
    }

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    if memberStudents.isEmpty {
                        Text("Sans groupe".tr)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(memberStudents) { student in
                            HStack {
                                Text(student.fullName)
                                Spacer()
                                Button {
                                    if let sid = student.id, let gid = group.id {
                                        Task {
                                            try? await viewModel.removeStudent(sid, fromGroup: gid, classID: classID)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                        }
                    }
                    if !nonMemberStudents.isEmpty {
                        Divider()
                        Text("Ajouter".tr)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(nonMemberStudents) { student in
                            HStack {
                                Text(student.fullName)
                                    .font(.caption)
                                Spacer()
                                Button {
                                    if let sid = student.id, let gid = group.id {
                                        Task {
                                            try? await viewModel.addStudent(sid, toGroup: gid, classID: classID)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "person.3.fill")
                        .foregroundColor(.blue)
                    Text(group.name)
                        .font(.headline)
                    Text("(\(memberStudents.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
            .padding(.vertical, 4)
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
                        Label("Compétence".tr, systemImage: "plus.circle")
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
                        TextField("Libellé de la compétence".tr, text: $newCompetencyLabel)
                            .textFieldStyle(.roundedBorder)
                        Button("OK".tr) {
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
