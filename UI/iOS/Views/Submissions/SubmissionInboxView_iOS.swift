//
//  SubmissionInboxView_iOS.swift
//  MathClassApp
//

import SwiftUI

/// iPad-facing submission inbox (ISSUE-002).
/// Mirrors `SubmissionInboxView_macOS` with a `NavigationSplitView`-friendly
/// layout. Each row leads to `SubmissionDetailView_iOS`. Live-updated via
/// `TeacherViewModel.recentSubmissions`, which is now fanned out across all
/// the teacher's assignments (ISSUE-005).
struct SubmissionInboxView_iOS: View {
    @ObservedObject var viewModel: TeacherViewModel
    @State private var selectedClassID: String?
    @State private var searchText: String = ""

    private var filteredSubmissions: [Submission] {
        let all = viewModel.recentSubmissions
        let byClass: [Submission]
        if let classID = selectedClassID {
            byClass = all.filter {
                viewModel.studentDirectory[$0.studentID]?.classID == classID
            }
        } else {
            byClass = all
        }

        guard !searchText.isEmpty else { return byClass }
        let needle = searchText.lowercased()
        return byClass.filter { sub in
            let student = viewModel.studentDirectory[sub.studentID]
            let exerciseTitle = viewModel.exercises.first { $0.id == sub.exerciseID }?.displayTitle ?? ""
            return student?.fullName.lowercased().contains(needle) == true
                || exerciseTitle.lowercased().contains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            classFilter
            Divider()
            content
        }
        .searchable(text: $searchText, prompt: "Rechercher un élève ou un exercice")
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
            Text(LocalizationManager.shared.format(filteredSubmissions.count == 1 ? "%@ soumission" : "%@ soumissions", String(filteredSubmissions.count)))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if filteredSubmissions.isEmpty {
            emptyState
        } else {
            List {
                ForEach(filteredSubmissions, id: \.id) { submission in
                    NavigationLink {
                        SubmissionDetailView_iOS(submission: submission, viewModel: viewModel)
                    } label: {
                        submissionRow(submission)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("Aucune soumission".tr)
                .font(.headline)
            Text("Les travaux soumis par vos élèves apparaîtront ici en temps réel.".tr)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func submissionRow(_ submission: Submission) -> some View {
        let studentName = viewModel.studentDirectory[submission.studentID]?.fullName
            ?? "Élève \(submission.studentID.prefix(6))"
        let exerciseTitle = viewModel.exercises.first { $0.id == submission.exerciseID }?.displayTitle
            ?? "Exercice inconnu"

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(studentName)
                    .font(.body)
                    .lineLimit(1)
                Text(exerciseTitle + " — " + LocalizationManager.shared.format("Essai %@", String(submission.attemptNumber)))
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
}
