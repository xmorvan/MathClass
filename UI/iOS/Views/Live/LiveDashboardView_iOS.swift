//
//  LiveDashboardView_iOS.swift
//  MathClassApp
//
//  iPad teacher's live grid for the active session of an active period.
//  Mirrors LiveDashboardView_macOS but with a more compact layout that
//  reads well on a 11"/12.9" iPad in portrait or landscape.
//

import SwiftUI

struct LiveDashboardView_iOS: View {
    @ObservedObject var viewModel: TeacherViewModel
    @State private var selectedClassID: String?
    @State private var pushMessage: String?

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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if students.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                        ForEach(students) { student in
                            StudentTile_iOS(
                                student: student,
                                latestSubmission: latestSubmission(for: student),
                                exerciseTitle: latestExerciseTitle(for: student),
                                pushableExercises: pushableExercises(for: student),
                                onPushExercise: { exerciseID in
                                    pushExercise(exerciseID, to: student)
                                }
                            )
                        }
                    }
                    .padding()
        .alert(
            pushMessage ?? "",
            isPresented: Binding(get: { pushMessage != nil }, set: { if !$0 { pushMessage = nil } })
        ) {
            Button("OK".tr, role: .cancel) { pushMessage = nil }
        }
                }
            }
        }
        .padding()
        // Runs on appear, when the class list first arrives, and when the
        // teacher switches class. `selectClass` loads that class's roster:
        // `studentsInClass` only sees the selected class's students, so
        // without it the dashboard showed "no students" unless the class
        // had been opened in the Classes screen first.
        .task(id: activeClassID) {
            guard let classID = activeClassID else { return }
            viewModel.selectClass(classID)
            viewModel.startListeningToPeriods(classID: classID)
        }
        .onChange(of: activePeriod?.id) { _, periodID in
            if let periodID {
                viewModel.startListeningToSessions(periodID: periodID)
            }
        }
        .onDisappear {
            // Without this the period + session listeners outlive the view
            // and the per-class fan-out accumulates as the teacher class-
            // switches (ISSUE-014 §4.A.3).
            viewModel.stopListeningToPeriods()
            viewModel.stopListeningToSessions()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Vue d'ensemble en direct".tr)
                    .font(.title3)
                    .bold()
                if let period = activePeriod {
                    Text(period.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Aucune séance active".tr)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if viewModel.classes.count > 1 {
                Picker("Classe".tr, selection: Binding(
                    get: { activeClassID ?? "" },
                    set: { selectedClassID = $0 }
                )) {
                    ForEach(viewModel.classes) { c in
                        Text(c.name).tag(c.id ?? "")
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.3.sequence")
                .font(.system(size: 36))
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
        return viewModel.exercises.first(where: { $0.id == sub.exerciseID })?.displayTitle
    }

    private var activeSession: Session? {
        viewModel.sessions.first(where: { $0.isActive })
    }

    /// Exercises the teacher can push to a specific student right now.
    /// Excludes ones the student already submitted in the active period.
    private func pushableExercises(for student: Student) -> [Exercise] {
        guard let sid = student.id else { return [] }
        let completedIDs: Set<String> = Set(
            viewModel.submissionRepo.submissions
                .filter { $0.studentID == sid }
                .map { $0.exerciseID }
        )
        return viewModel.exercises.filter { ex in
            guard let id = ex.id else { return false }
            return !completedIDs.contains(id)
        }
    }

    private func pushExercise(_ exerciseID: String, to student: Student) {
        guard let studentID = student.id, let classID = activeClassID else { return }
        Task {
            do {
                try await viewModel.pushExercise(exerciseID, to: studentID, classID: classID)
                pushMessage = LocalizationManager.shared.format("Exercice envoyé à %@.", student.firstName)
            } catch {
                pushMessage = error.localizedDescription
            }
        }
    }
}

private struct StudentTile_iOS: View {
    let student: Student
    let latestSubmission: Submission?
    let exerciseTitle: String?
    let pushableExercises: [Exercise]
    let onPushExercise: (String) -> Void

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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(student.fullName)
                    .font(.subheadline).bold()
                Spacer()
                if let level = student.level {
                    Text("N\(level)")
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(4)
                }
            }
            if let title = exerciseTitle {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else {
                Text("Pas encore commencé".tr)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack {
                Circle().fill(statusColor).frame(width: 6, height: 6)
                Text(statusKey.tr).font(.caption2)
                Spacer()
                if statusKey == "Terminé" && !pushableExercises.isEmpty {
                    Menu {
                        ForEach(pushableExercises) { exercise in
                            Button(exercise.displayTitle) {
                                if let id = exercise.id {
                                    onPushExercise(id)
                                }
                            }
                        }
                    } label: {
                        Label("Plus".tr, systemImage: "plus.circle")
                            .font(.caption2)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.08)))
    }
}
