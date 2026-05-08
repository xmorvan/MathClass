//
//  SubmissionDetailView_macOS.swift
//  MathClassApp
//

import SwiftUI

/// Detail view for a single student submission.
/// Renders: student + exercise context, the original PNG drawing, the
/// recognised LaTeX steps with per-step correction marks, and a summary
/// of the final result.
struct SubmissionDetailView_macOS: View {
    let submission: Submission
    @ObservedObject var viewModel: TeacherViewModel

    private var student: Student? {
        viewModel.studentDirectory[submission.studentID]
    }

    private var exercise: Exercise? {
        viewModel.exercises.first { $0.id == submission.exerciseID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                exerciseContext
                Divider()
                drawingSection
                Divider()
                stepsSection
            }
            .padding()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(student?.fullName ?? "Élève \(submission.studentID.prefix(6))")
                    .font(.title2)
                    .bold()
                Spacer()
                resultChip
            }
            HStack(spacing: 12) {
                Label(exercise?.title ?? "Exercice inconnu", systemImage: "book")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Label("Essai \(submission.attemptNumber)", systemImage: "number.circle")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Label(
                    submission.timestamp.formatted(date: .abbreviated, time: .shortened),
                    systemImage: "clock"
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var resultChip: some View {
        if let result = submission.finalResult {
            HStack(spacing: 6) {
                Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.isSuccess ? .green : .red)
                Text(result.displayName)
                    .font(.headline)
                    .foregroundColor(result.isSuccess ? .green : .red)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .foregroundColor(.orange)
                Text("En attente de correction".tr)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Exercise context

    @ViewBuilder
    private var exerciseContext: some View {
        if let exercise = exercise {
            VStack(alignment: .leading, spacing: 8) {
                Text("Énoncé".tr)
                    .font(.headline)
                KaTeXView(content: exercise.statement, mode: .preview, fontSize: 16, minHeight: 60)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(6)

                if !exercise.expectedAnswer.isEmpty {
                    Text("Réponse attendue".tr)
                        .font(.headline)
                    KaTeXView(
                        content: "$\(exercise.expectedAnswer)$",
                        mode: .preview,
                        fontSize: 14,
                        minHeight: 40
                    )
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(6)
                }
            }
        }
    }

    // MARK: - Drawing

    private var drawingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Travail manuscrit".tr)
                .font(.headline)
            if let path = submission.pngURL, !path.isEmpty {
                AsyncImageFromStorage(path: path)
            } else {
                Text("Aucun PNG enregistré pour cette soumission.".tr)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Steps + correction

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Étapes reconnues".tr)
                .font(.headline)

            if submission.latexSteps.isEmpty {
                Text("Aucune étape reconnue.".tr)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(submission.latexSteps.enumerated()), id: \.offset) { index, step in
                    stepRow(index: index, step: step)
                }
            }
        }
    }

    @ViewBuilder
    private func stepRow(index: Int, step: String) -> some View {
        let stepResults = submission.correctionResult?.stepResults
        let firstErrorIndex = submission.correctionResult?.firstErrorIndex
        let isCorrect: Bool? = stepResults.flatMap { results in
            index < results.count ? results[index] : nil
        }

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                stepIcon(isCorrect: isCorrect)

                Text("Étape \(index + 1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .leading)

                KaTeXView(
                    content: "$\(step)$",
                    mode: .preview,
                    fontSize: 14,
                    minHeight: 30
                )
            }

            if firstErrorIndex == index {
                Text("← Première erreur".tr)
                    .font(.caption)
                    .foregroundColor(.red)
                    .bold()
                    .padding(.leading, 88)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func stepIcon(isCorrect: Bool?) -> some View {
        if let isCorrect = isCorrect {
            Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isCorrect ? .green : .red)
        } else {
            Image(systemName: "circle")
                .foregroundColor(.secondary)
        }
    }
}
