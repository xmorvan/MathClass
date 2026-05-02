//
//  StatisticsView_macOS.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 14.11.2024.
//

import SwiftUI

/// Teacher statistics dashboard for macOS.
/// Three tabs: Per-student, Per-exercise, Per-class.
struct StatisticsView_macOS: View {
    @ObservedObject var viewModel: TeacherViewModel
    @State private var selectedTab: StatTab = .perStudent
    @State private var selectedClassID: String?
    @State private var isLoadingStats: Bool = false
    @State private var submissions: [Submission] = []

    enum StatTab: String, CaseIterable {
        case perStudent = "Par élève"
        case perExercise = "Par exercice"
        case perClass = "Par classe"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with class selector and tabs
            statsHeader

            Divider()

            // Content
            if isLoadingStats {
                ProgressView("Chargement des statistiques…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if submissions.isEmpty && selectedClassID != nil {
                emptyState
            } else {
                switch selectedTab {
                case .perStudent:
                    StudentStatsListView_macOS(
                        viewModel: viewModel,
                        submissions: submissions,
                        classID: selectedClassID
                    )
                case .perExercise:
                    ExerciseStatsListView_macOS(
                        viewModel: viewModel,
                        submissions: submissions
                    )
                case .perClass:
                    ClassOverviewView_macOS(
                        viewModel: viewModel,
                        submissions: submissions,
                        classID: selectedClassID
                    )
                }
            }
        }
        .onChange(of: selectedClassID) { _, newID in
            // Switch the listeners to the new class. We no longer guess how
            // long Firestore needs to populate via Task.sleep — we observe
            // viewModel.assignments below and re-load whenever it changes.
            if let classID = newID {
                viewModel.assignmentRepo.startListening(classID: classID)
                viewModel.studentRepo.startListening(classID: classID)
            }
            Task { await loadSubmissions() }
        }
        .onChange(of: viewModel.assignments) { _, _ in
            // React to listener updates instead of sleeping for 500 ms and
            // hoping the snapshot has arrived.
            Task { await loadSubmissions() }
        }
        .onAppear {
            if selectedClassID == nil, let first = viewModel.classes.first {
                selectedClassID = first.id
            }
            if let classID = selectedClassID {
                viewModel.assignmentRepo.startListening(classID: classID)
                viewModel.studentRepo.startListening(classID: classID)
                Task { await loadSubmissions() }
            }
        }
    }

    // MARK: - Header

    private var statsHeader: some View {
        HStack {
            Text("Statistiques")
                .font(.title2)
                .bold()

            Spacer()

            // Class selector
            Picker("Classe", selection: $selectedClassID) {
                Text("Toutes les classes").tag(nil as String?)
                ForEach(viewModel.classes) { classroom in
                    Text(classroom.name).tag(classroom.id as String?)
                }
            }
            .frame(width: 200)

            // Tab picker
            Picker("Vue", selection: $selectedTab) {
                ForEach(StatTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)

            Button {
                Task { await loadSubmissions() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Aucune donnée")
                .font(.headline)
            Text("Les statistiques apparaîtront lorsque des élèves auront soumis des travaux.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadSubmissions() async {
        isLoadingStats = true
        do {
            if let classID = selectedClassID {
                // Load all assignments for this class, then all their submissions
                let assignments = viewModel.assignments.filter { $0.classID == classID }
                var allSubmissions: [Submission] = []
                for assignment in assignments {
                    guard let id = assignment.id else { continue }
                    let subs = try await viewModel.submissionRepo.getSubmissions(assignmentID: id)
                    allSubmissions.append(contentsOf: subs)
                }
                self.submissions = allSubmissions
            } else {
                // Load all submissions for all assignments
                var allSubmissions: [Submission] = []
                for assignment in viewModel.assignments {
                    guard let id = assignment.id else { continue }
                    let subs = try await viewModel.submissionRepo.getSubmissions(assignmentID: id)
                    allSubmissions.append(contentsOf: subs)
                }
                self.submissions = allSubmissions
            }
        } catch {
            print("Erreur chargement statistiques: \(error.localizedDescription)")
        }
        isLoadingStats = false
    }
}

// MARK: - Simple Stat Card (macOS)

struct StatCard_macOS: View {
    let title: String
    let value: String
    var subtitle: String?
    var color: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(color)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 120, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
    }
}
