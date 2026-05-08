//
//  LiveDashboardView_macOS.swift
//  MathClass
//
//  Real-time per-student grid for the active session of an active
//  period. Each tile shows the student's name, the exercise they're
//  currently on (best-effort: derived from the most recent submission),
//  and a status chip (Working / Done / Pending). Updates via the
//  existing submission listener.
//

import SwiftUI

struct LiveDashboardView_macOS: View {
    @ObservedObject var viewModel: TeacherViewModel
    @State private var selectedClassID: String?
    @State private var showCreatePeriod: Bool = false

    private var activeClassID: String? {
        selectedClassID ?? viewModel.classes.first?.id
    }

    private var students: [Student] {
        guard let classID = activeClassID else { return [] }
        return viewModel.studentsInClass(classID)
    }

    private var activePeriod: Period? {
        guard let classID = activeClassID else { return nil }
        return viewModel.periods.first(where: { $0.classID == classID && $0.isActive })
    }

    private var activeSession: Session? {
        viewModel.sessions.first(where: { $0.isActive })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            if students.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                        ForEach(students) { student in
                            StudentTile(
                                student: student,
                                latestSubmission: latestSubmission(for: student),
                                exerciseTitle: latestExerciseTitle(for: student),
                                onPushMore: {
                                    pushMore(for: student)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .padding()
        .onAppear {
            if let classID = activeClassID {
                viewModel.startListeningToPeriods(classID: classID)
                if let pid = activePeriod?.id {
                    viewModel.startListeningToSessions(periodID: pid)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Vue d'ensemble en direct".tr)
                    .font(.title)
                    .bold()
                if let period = activePeriod {
                    Text(period.name)
                        .foregroundColor(.secondary)
                } else {
                    Text("Aucune séance active".tr)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if viewModel.classes.count > 1 {
                Picker("Classe".tr, selection: Binding(get: { activeClassID ?? "" }, set: { selectedClassID = $0 })) {
                    ForEach(viewModel.classes) { c in
                        Text(c.name).tag(c.id ?? "")
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220)
            }
            Button {
                showCreatePeriod = true
            } label: {
                Label("Nouvelle séance".tr, systemImage: "calendar.badge.plus")
            }
        }
        .sheet(isPresented: $showCreatePeriod) {
            CreatePeriodView_macOS(viewModel: viewModel)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.3.sequence")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Aucun élève inscrit".tr)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func latestSubmission(for student: Student) -> Submission? {
        guard let sid = student.id else { return nil }
        return viewModel.submissionRepo.submissions
            .filter { $0.studentID == sid }
            .sorted { $0.timestamp > $1.timestamp }
            .first
    }

    private func latestExerciseTitle(for student: Student) -> String? {
        guard let sub = latestSubmission(for: student) else { return nil }
        return viewModel.exercises.first(where: { $0.id == sub.exerciseID })?.title
    }

    private func pushMore(for student: Student) {
        // Best-effort: append a "needs more exercises" marker to the active
        // session's exercise list. Until a teacher picks specific extra
        // exercises in a follow-up flow, this is just a TODO placeholder.
        // The proper flow lives in CreateAssignmentView_macOS once the
        // session-aware UI lands.
        // (Slice 11 polish item.)
    }
}

private struct StudentTile: View {
    let student: Student
    let latestSubmission: Submission?
    let exerciseTitle: String?
    let onPushMore: () -> Void

    private var statusKey: String {
        guard let sub = latestSubmission else { return "En attente" }
        if sub.finalResult == nil { return "En cours" }
        return "Terminé"
    }

    private var statusColor: Color {
        guard let sub = latestSubmission else { return .gray }
        if sub.finalResult == nil { return .blue }
        switch sub.finalResult {
        case .success1st, .success2nd: return .green
        case .failed: return .orange
        case .none: return .blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(student.fullName)
                    .font(.headline)
                Spacer()
                if let level = student.level {
                    Text("N\(level)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(4)
                }
            }
            if let title = exerciseTitle {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else {
                Text("Pas encore commencé".tr)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusKey.tr)
                    .font(.caption)
                Spacer()
                if statusKey == "Terminé" {
                    Button {
                        onPushMore()
                    } label: {
                        Label("Plus".tr, systemImage: "plus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.06)))
    }
}
