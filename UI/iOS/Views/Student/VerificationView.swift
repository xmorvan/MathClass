//
//  VerificationView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import SwiftUI

/// Shows the recognized LaTeX steps for the student to review before submission.
/// During recognition, shows a loading state.
/// After recognition, the student can confirm the steps or go back to redraw.
struct VerificationView: View {
    @ObservedObject var viewModel: SubmissionViewModel
    @State private var editableSteps: [String] = []

    var onCancel: () -> Void

    init(viewModel: SubmissionViewModel, onCancel: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onCancel = onCancel
        // editableSteps is hydrated from viewModel.recognizedSteps via the
        // .onChange / .onAppear handlers in `body` — initialising it from
        // the constructor's snapshot was wrong because the recognised steps
        // are populated asynchronously after this init runs (the sheet is
        // mounted while phase = .recognizing, then the steps land while we
        // remain mounted).
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if viewModel.phase == .recognizing {
                recognizingView
            } else if viewModel.phase == .submitting {
                submittingView
            } else {
                reviewContent
            }

            Divider()

            actionButtons
        }
        // Hydrate the local editable copy as soon as the recognised steps
        // arrive (and any time they change due to a retry). Without this,
        // the TextField list stayed empty even after recognition completed.
        .onAppear { editableSteps = viewModel.recognizedSteps }
        .onChange(of: viewModel.recognizedSteps) { _, newValue in
            editableSteps = newValue
        }
        .alert("Erreur", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "Une erreur est survenue.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Vérification")
                .font(.title2)
                .bold()
            Spacer()
            Text(viewModel.exercise.title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    // MARK: - Loading States

    private var recognizingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Reconnaissance de l'écriture…")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Analyse de votre travail en cours.")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var submittingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Soumission en cours…")
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Review Content

    private var reviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if editableSteps.isEmpty {
                    emptyStepsView
                } else {
                    stepsListView
                }

                // Preview
                if !editableSteps.isEmpty {
                    Text("Aperçu")
                        .font(.headline)
                        .padding(.top, 8)

                    let combined = editableSteps.enumerated().map { (i, step) in
                        "Étape \(i + 1): $\(step)$"
                    }.joined(separator: "\n")

                    KaTeXView(content: combined, mode: .preview, fontSize: 18, minHeight: 60)
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(8)
                }
            }
            .padding()
        }
    }

    private var emptyStepsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("Aucune étape reconnue")
                .font(.headline)

            Text("La reconnaissance automatique sera disponible prochainement.\nVous pouvez soumettre directement votre travail.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var stepsListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Étapes reconnues")
                .font(.headline)

            Text("Vérifiez que ces étapes correspondent à votre travail.")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(editableSteps.indices, id: \.self) { index in
                HStack(alignment: .top) {
                    Text("Étape \(index + 1)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .leading)

                    TextField("LaTeX", text: $editableSteps[index])
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                onCancel()
            } label: {
                Label("Refaire", systemImage: "arrow.uturn.left")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                Task {
                    await viewModel.confirmAndSubmit(confirmedSteps: editableSteps)
                }
            } label: {
                Label("Soumettre", systemImage: "paperplane.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.phase == .submitting)
        }
        .padding()
    }
}
