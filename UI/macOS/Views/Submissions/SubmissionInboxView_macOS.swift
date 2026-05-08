//
//  SubmissionInboxView_macOS.swift
//  MathClassApp
//

import SwiftUI

/// Teacher-facing inbox of student submissions across all classes.
/// List on the left, detail (PNG + LaTeX steps + per-step correction) on the right.
/// Live-updated via TeacherViewModel.recentSubmissions (driven by
/// SubmissionRepository.startListeningForTeacher).
struct SubmissionInboxView_macOS: View {
    @ObservedObject var viewModel: TeacherViewModel
    @State private var selectedSubmissionID: String?
    @State private var selectedClassID: String?

    private var filteredSubmissions: [Submission] {
        let all = viewModel.recentSubmissions
        guard let classID = selectedClassID else { return all }
        // Filter by mapping submission.studentID -> student.classID
        return all.filter { sub in
            viewModel.studentDirectory[sub.studentID]?.classID == classID
        }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                classFilter
                Divider()
                submissionList
            }
            .frame(minWidth: 320)

            detailPane
                .frame(minWidth: 500)
        }
        .navigationTitle("Soumissions".tr)
    }

    // MARK: - Class filter

    private var classFilter: some View {
        HStack {
            Picker("Classe".tr, selection: $selectedClassID) {
                Text("Toutes les classes".tr).tag(String?.none)
                ForEach(viewModel.classes, id: \.id) { classroom in
                    if let id = classroom.id {
                        Text(classroom.name).tag(String?.some(id))
                    }
                }
            }
            .pickerStyle(.menu)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Submission list

    private var submissionList: some View {
        Group {
            if filteredSubmissions.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("Aucune soumission".tr)
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Les soumissions des élèves apparaîtront ici dès qu'elles seront envoyées.".tr)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredSubmissions, id: \.id, selection: $selectedSubmissionID) { submission in
                    submissionRow(submission)
                        .tag(submission.id)
                }
            }
        }
    }

    private func submissionRow(_ submission: Submission) -> some View {
        let studentName = viewModel.studentDirectory[submission.studentID]?.fullName
            ?? "Élève \(submission.studentID.prefix(6))"
        let exerciseTitle = viewModel.exercises.first { $0.id == submission.exerciseID }?.title
            ?? "Exercice inconnu"

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(studentName)
                    .font(.body)
                    .lineLimit(1)
                Text("\(exerciseTitle) — Essai \(submission.attemptNumber)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(submission.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            resultChip(submission)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func resultChip(_ submission: Submission) -> some View {
        if let result = submission.finalResult {
            HStack(spacing: 4) {
                Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.isSuccess ? .green : .red)
                Text(result.displayName)
                    .font(.caption)
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .foregroundColor(.orange)
                Text("En attente".tr)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailPane: some View {
        if let id = selectedSubmissionID,
           let submission = filteredSubmissions.first(where: { $0.id == id }) {
            SubmissionDetailView_macOS(submission: submission, viewModel: viewModel)
                .id(id)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
                Text("Sélectionnez une soumission".tr)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
