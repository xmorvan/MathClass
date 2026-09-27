//
//  LiveDashboardView_macOS.swift
//  MathClass
//
//  Real-time per-student grid for the assignment the class is working on
//  (the one of the latest copy, else the newest active one). Each tile
//  shows the exercise the student is on, their progress through the
//  assignment and what needs the teacher: a mistake to fix, a student
//  gone quiet, the assignment finished. Updates via the submission
//  listener; idle times refresh every 30 seconds.
//

import SwiftUI

struct LiveDashboardView_macOS: View {
    @ObservedObject var viewModel: TeacherViewModel
    @State private var selectedClassID: String?
    @State private var showCreatePeriod: Bool = false
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
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let progresses = students.map { progress(for: $0, now: context.date) }
                    VStack(alignment: .leading, spacing: 12) {
                        summary(progresses)
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                                ForEach(Array(zip(students, progresses)), id: \.0.id) { student, progress in
                                    StudentTile(
                                        student: student,
                                        progress: progress,
                                        exerciseTitle: exerciseTitle(progress?.currentExerciseID),
                                        pushableExercises: pushableExercises(for: student),
                                        onPushExercise: { exerciseID in
                                            pushExercise(exerciseID, to: student)
                                        }
                                    )
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
        }
        .padding()
        .alert(
            pushMessage ?? "",
            isPresented: Binding(get: { pushMessage != nil }, set: { if !$0 { pushMessage = nil } })
        ) {
            Button("OK".tr, role: .cancel) { pushMessage = nil }
        }
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
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Vue d'ensemble en direct".tr)
                    .font(.title)
                    .bold()
                if let assignment = lessonAssignment {
                    Text(assignment.titleWithMode)
                        .foregroundColor(.secondary)
                } else if let period = activePeriod {
                    Text(period.name)
                        .foregroundColor(.secondary)
                } else {
                    Text("Aucun devoir actif".tr)
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

    private var lessonAssignment: Assignment? {
        guard let classID = activeClassID else { return nil }
        return viewModel.lessonAssignment(classID: classID, studentIDs: Set(students.compactMap(\.id)))
    }

    private func progress(for student: Student, now: Date) -> LiveProgress? {
        guard let assignment = lessonAssignment else { return nil }
        return viewModel.liveProgress(of: student, in: assignment, now: now)
    }

    private func exerciseTitle(_ exerciseID: String?) -> String? {
        guard let exerciseID else { return nil }
        return viewModel.exercises.first(where: { $0.id == exerciseID })?.displayTitle
    }

    /// One line for the whole class: who works, who is done, who needs help.
    private func summary(_ progresses: [LiveProgress?]) -> some View {
        let counts = progresses.liveCounts
        return HStack(spacing: 16) {
            SummaryChip(count: counts.working, label: "au travail".tr, color: .blue)
            SummaryChip(count: counts.finished, label: "ont fini".tr, color: .green)
            SummaryChip(count: counts.needsFix, label: "erreur à corriger".tr, color: .orange)
            SummaryChip(count: counts.idle, label: "inactifs".tr, color: .yellow)
            SummaryChip(count: counts.notStarted, label: "pas commencé".tr, color: .gray)
        }
        .padding(.horizontal)
    }

    /// Exercises the teacher can push to a specific student right now.
    /// Excludes exercises the student has already submitted in this period
    /// — they should be tried with fresh exercises, not the same ones.
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

private struct SummaryChip: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count)").bold()
            Text(label).foregroundColor(.secondary)
        }
        .font(.callout)
    }
}

private struct StudentTile: View {
    let student: Student
    let progress: LiveProgress?
    let exerciseTitle: String?
    let pushableExercises: [Exercise]
    let onPushExercise: (String) -> Void

    private var status: (label: String, color: Color) {
        switch progress?.state ?? .notStarted {
        case .notStarted: return ("Pas encore commencé".tr, .gray)
        case .working: return ("Au travail".tr, .blue)
        case .needsFix: return ("Erreur à corriger".tr, .orange)
        case .idle(let minutes): return (LocalizationManager.shared.format("Inactif depuis %@ min", String(minutes)), .yellow)
        case .finished: return ("Devoir terminé".tr, .green)
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
            Text(exerciseTitle ?? " ")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
            if let progress, progress.assigned > 0 {
                HStack(spacing: 8) {
                    ProgressView(value: Double(progress.done), total: Double(progress.assigned))
                        .tint(status.color)
                    Text("\(progress.done)/\(progress.assigned)")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            HStack {
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
                Text(status.label)
                    .font(.caption)
                if let progress, progress.done > 0 {
                    Text(LocalizationManager.shared.format("· %@ réussis", String(progress.succeeded)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if progress?.state == .finished && !pushableExercises.isEmpty {
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
                            .font(.caption)
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                    .fixedSize()
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(status.color.opacity(progress?.state == .needsFix ? 0.10 : 0.04)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(status.color.opacity(progress?.state == .needsFix ? 0.5 : 0), lineWidth: 1)
        )
    }
}
