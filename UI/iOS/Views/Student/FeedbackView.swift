//
//  FeedbackView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import SwiftUI

/// Mode-dependent feedback display after correction.
///
/// - Differentiation: Shows which step is wrong (firstErrorIndex).
///   Offers 2nd chance if allowed.
/// - Levels: Shows correct/incorrect only. Offers 2nd chance.
/// - Evaluation: Shows "submitted, no feedback" — teacher sees results.
struct FeedbackView: View {
    @ObservedObject var viewModel: SubmissionViewModel

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    if !viewModel.showsFeedback {
                        evaluationFeedback
                    } else if let result = viewModel.finalResult {
                        resultFeedback(result: result)
                    } else {
                        pendingFeedback
                    }
                }
                .padding()
            }

            Divider()

            actionButtons
        }
        .alert("Erreur".tr, isPresented: $viewModel.showError) {
            Button("OK".tr, role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "Une erreur est survenue.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Résultat".tr)
                .font(.title2)
                .bold()
            Spacer()
            Text(viewModel.exercise.displayTitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    // MARK: - Evaluation Mode (no feedback)

    private var evaluationFeedback: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Soumission enregistrée".tr)
                .font(.title2)
                .bold()

            Text("Votre travail a été envoyé.\nVotre professeur verra les résultats.".tr)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Result Feedback (differentiation / levels)

    @ViewBuilder
    private func resultFeedback(result: SubmissionResult) -> some View {
        // Result icon and message
        VStack(spacing: 16) {
            resultIcon(result)

            // A failed first attempt with a second chance is not a verdict
            // yet: encourage the student instead of announcing "Échoué".
            Text(viewModel.canRetry ? "Pas encore".tr : result.displayName)
                .font(.title2)
                .bold()
                .foregroundColor(viewModel.canRetry ? .orange : resultColor(result))

            resultMessage(result)
        }

        // Notation note (any mode where correction ran). Always rendered
        // as a separate banner that does NOT mark anything wrong. The key
        // is language-neutral; Localizations.swift holds the FR/EN strings.
        if let correction = viewModel.correctionResult,
           let key = correction.notationNoteKey, !key.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Note de notation".tr)
                        .font(.subheadline)
                        .bold()
                    Text(NotationNote.localizedMessage(forKey: key))
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(10)
        }

        // Step details (differentiation mode only)
        if viewModel.showsErrorStep, let correction = viewModel.correctionResult {
            stepDetails(correction: correction)
        }

        // Level progression (levels mode only)
        if let progress = viewModel.levelProgress {
            levelProgressView(progress: progress)
        }
    }

    private func resultIcon(_ result: SubmissionResult) -> some View {
        Group {
            switch result {
            case .success1st:
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
            case .success2nd:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: viewModel.canRetry ? "arrow.uturn.backward.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(viewModel.canRetry ? .orange : .red)
            }
        }
    }

    private func resultColor(_ result: SubmissionResult) -> Color {
        result.isSuccess ? .green : .red
    }

    @ViewBuilder
    private func resultMessage(_ result: SubmissionResult) -> some View {
        switch result {
        case .success1st:
            Text("Excellent ! Réponse correcte du premier coup.".tr)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        case .success2nd:
            Text("Bien joué ! Réponse correcte au deuxième essai.".tr)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        case .failed:
            Text(viewModel.canRetry
                 ? "Une étape est à revoir.\nCorrigez-la et réessayez : vous avez une deuxième chance.".tr
                 : "La réponse n'est pas correcte.\nRévisez cette notion pour progresser.".tr)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Step Details (differentiation mode)

    private func stepDetails(correction: CorrectionResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Détail par étape".tr)
                .font(.headline)

            ForEach(Array(correction.stepResults.enumerated()), id: \.offset) { index, isCorrect in
                HStack {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isCorrect ? .green : .red)

                    Text(LocalizationManager.shared.format("Étape %@", String(index + 1)))
                        .font(.body)

                    if index < viewModel.recognizedSteps.count {
                        KaTeXView(
                            content: "$\(viewModel.recognizedSteps[index])$",
                            mode: .preview,
                            fontSize: 14,
                            minHeight: 30
                        )
                    }
                }

                if let errorIndex = correction.firstErrorIndex, index == errorIndex {
                    Text("← Première erreur ici".tr)
                        .font(.caption)
                        .foregroundColor(.red)
                        .bold()
                        .padding(.leading, 30)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Level Progression (levels mode)

    private func levelProgressView(progress: AssignmentModeHandler.LevelProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progression".tr)
                .font(.headline)

            if progress.didAdvance {
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(.purple)
                        .font(.title2)
                    VStack(alignment: .leading) {
                        Text("Niveau supérieur !".tr)
                            .font(.headline)
                            .foregroundColor(.purple)
                        Text("Vous passez au niveau \(progress.currentLevel).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                Text("Réussites consécutives :".tr)
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: index < progress.consecutiveCorrect ? "star.fill" : "star")
                        .foregroundColor(index < progress.consecutiveCorrect ? .yellow : .gray.opacity(0.3))
                }

                Text("/ 3")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Text("Niveau actuel :".tr)
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(1...5, id: \.self) { level in
                    Image(systemName: level <= progress.currentLevel ? "circle.fill" : "circle")
                        .foregroundColor(level <= progress.currentLevel ? .purple : .gray.opacity(0.3))
                        .font(.system(size: 10))
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Pending (waiting for correction)

    private var pendingFeedback: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Correction en cours…".tr)
                .font(.headline)

            Text("Votre travail est en cours de vérification.".tr)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            if viewModel.canRetry {
                Button {
                    viewModel.startRetry()
                } label: {
                    Label("Réessayer".tr, systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }

            Spacer()

            Button {
                viewModel.moveToNext()
            } label: {
                Label("Suivant".tr, systemImage: "arrow.right")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
