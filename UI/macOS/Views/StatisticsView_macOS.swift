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
    @State private var exportError: String?
    @State private var showExportError: Bool = false
    @State private var lastExportURL: URL?
    @State private var showExportSuccess: Bool = false

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
            Text("Statistiques".tr)
                .font(.title2)
                .bold()

            Spacer()

            // Class selector
            Picker("Classe".tr, selection: $selectedClassID) {
                Text("Toutes les classes".tr).tag(nil as String?)
                ForEach(viewModel.classes) { classroom in
                    Text(classroom.name).tag(classroom.id as String?)
                }
            }
            .frame(width: 200)

            // Tab picker
            Picker("Vue".tr, selection: $selectedTab) {
                ForEach(StatTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue.tr)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)

            Button {
                Task { await loadSubmissions() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }

            Button {
                exportCurrentTabToPDF()
            } label: {
                Label("Exporter en PDF".tr, systemImage: "square.and.arrow.up")
            }
            .disabled(submissions.isEmpty)
        }
        .padding()
        .alert("Erreur".tr, isPresented: $showExportError) {
            Button("OK".tr, role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .alert("PDF exporté".tr, isPresented: $showExportSuccess) {
            Button("OK".tr, role: .cancel) {}
            if let url = lastExportURL {
                Button("Ouvrir".tr) { NSWorkspace.shared.open(url) }
            }
        } message: {
            Text(lastExportURL?.path ?? "")
        }
    }

    @MainActor
    private func exportCurrentTabToPDF() {
        let className = viewModel.classes.first(where: { $0.id == selectedClassID })?.name ?? "Toutes les classes"
        let baseTitle = String(format: "Rapport - %@".tr, className)
        let title = "\(baseTitle) — \(selectedTab.rawValue.tr)"
        let report = StatisticsPDFReport_macOS(
            title: title,
            generatedAt: Date(),
            tab: selectedTab,
            viewModel: viewModel,
            submissions: submissions,
            classID: selectedClassID
        )
        do {
            let url = try PDFExporter.exportToPDF(view: report, fileName: title)
            // The export lands in the sandbox's hidden temp folder: let the
            // teacher choose where to keep it.
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = url.lastPathComponent
            panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            lastExportURL = destination
            showExportSuccess = true
        } catch {
            exportError = error.localizedDescription
            showExportError = true
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Aucune donnée".tr)
                .font(.headline)
            Text("Les statistiques apparaîtront lorsque des élèves auront soumis des travaux.".tr)
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
            Text(title.tr)
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

// MARK: - Rate Bar (macOS)

/// Success-rate bar drawn with shapes: unlike `ProgressView` it also
/// renders in PDF exports (ImageRenderer cannot draw AppKit controls).
struct RateBar_macOS: View {
    let rate: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.2))
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * CGFloat(min(max(rate, 0), 1)))
            }
        }
        .frame(height: 6)
    }
}
