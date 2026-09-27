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
    @ObservedObject private var network = NetworkMonitor.shared
    @State private var editableSteps: [String] = []
    /// Steps whose keyboard field is open. Students read the rendered
    /// formula; the field shows it in keyboard notation, never LaTeX.
    @State private var editingSteps: Set<Int> = []
    /// What the student types in each open field ("1/2", "x^2", "√2"),
    /// converted to LaTeX as they type.
    @State private var drafts: [Int: String] = [:]
    @FocusState private var focusedStep: Int?

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
        .alert("Erreur".tr, isPresented: $viewModel.showError) {
            Button("OK".tr, role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "Une erreur est survenue.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Vérification".tr)
                    .font(.title2)
                    .bold()
                Spacer()
                Text(viewModel.exercise.displayTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if !network.isOnline {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .foregroundColor(.orange)
                    Text("En attente de connexion".tr)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding()
    }

    // MARK: - Loading States

    private var recognizingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Reconnaissance de l'écriture…".tr)
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Analyse de votre travail en cours.".tr)
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
            Text("Soumission en cours…".tr)
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

            }
            .padding()
        }
    }

    private var emptyStepsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("Aucune ligne lue".tr)
                .font(.headline)

            Text("La reconnaissance n'a rien lu sur votre dessin.\nRetournez au dessin pour réécrire plus lisiblement, ou écrivez vos étapes au clavier.".tr)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button {
                    onCancel()
                } label: {
                    Label("Retour au dessin".tr, systemImage: "arrow.uturn.left")
                }
                .buttonStyle(.bordered)

                Button {
                    addStep()
                } label: {
                    Label("Écrire au clavier".tr, systemImage: "keyboard")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var stepsListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Étapes reconnues".tr)
                    .font(.headline)
                Spacer()
            }

            Text("Vérifiez que chaque ligne correspond à ce que vous avez écrit. Sinon, corrigez-la au clavier, supprimez-la ou ajoutez une ligne.".tr)
                .font(.caption)
                .foregroundColor(.secondary)

            // Each line is shown as a rendered formula; the LaTeX source
            // only opens on request (students are not expected to read it).
            ForEach(Array(editableSteps.enumerated()), id: \.offset) { index, step in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(LocalizationManager.shared.format("Ligne %@", String(index + 1)))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 56, alignment: .leading)

                        if let sentence = SubmissionViewModel.sentence(ofStep: step) {
                            Text(sentence)
                                .font(.title3)
                                .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48, alignment: .leading)
                        } else {
                            KaTeXView(
                                content: step.trimmingCharacters(in: .whitespaces).isEmpty ? "" : "$\(step)$",
                                mode: .preview,
                                fontSize: 22,
                                minHeight: 48
                            )
                            .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
                        }

                        Button {
                            toggleEditing(index)
                        } label: {
                            Image(systemName: "keyboard")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Modifier au clavier".tr)

                        // Remove a step the recognition invented or split.
                        Button {
                            removeStep(at: index)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Supprimer l'étape".tr)
                    }

                    if editingSteps.contains(index) {
                        stepEditor(index)
                    }
                }
                .padding(.vertical, 4)
            }

            Button {
                addStep()
            } label: {
                Label("Ajouter une ligne".tr, systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .padding(.leading, 68)
        }
    }

    /// Keyboard field of a step, in keyboard notation, with the symbols a
    /// tablet keyboard lacks. The rendered line above updates as they type.
    private func stepEditor(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Ex. : 3/4 + x^2 = √2".tr, text: draftBinding(index))
                .font(.title3)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedStep, equals: index)

            if SubmissionViewModel.sentence(ofStep: editableSteps.indices.contains(index) ? editableSteps[index] : "") == nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(PlainMath.keys, id: \.label) { key in
                            Button(key.label) {
                                draftBinding(index).wrappedValue += key.insert
                                focusedStep = index
                            }
                            .buttonStyle(.bordered)
                            .font(.body)
                        }
                    }
                }
                Text("Écrivez 1/2 pour une fraction, x^2 pour une puissance, √ pour une racine.".tr)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.leading, 68)
    }

    // MARK: - Step editing

    /// Steps actually sent for correction: blank lines are dropped.
    private var nonEmptySteps: [String] {
        editableSteps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Bounds-checked binding on what the student types: a step can be
    /// deleted while its field is still on screen. A sentence step stays a
    /// sentence; anything else is converted to LaTeX.
    private func draftBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { drafts[index] ?? "" },
            set: { newValue in
                guard editableSteps.indices.contains(index) else { return }
                drafts[index] = newValue
                if SubmissionViewModel.sentence(ofStep: editableSteps[index]) != nil {
                    editableSteps[index] = SubmissionViewModel.textStep(newValue).first ?? ""
                } else {
                    editableSteps[index] = PlainMath.toLatex(newValue)
                }
            }
        )
    }

    private func toggleEditing(_ index: Int) {
        guard editableSteps.indices.contains(index) else { return }
        if editingSteps.contains(index) {
            editingSteps.remove(index)
            return
        }
        let step = editableSteps[index]
        drafts[index] = SubmissionViewModel.sentence(ofStep: step) ?? PlainMath.fromLatex(step)
        editingSteps.insert(index)
        focusedStep = index
    }

    /// A line the recognition missed, typed at the keyboard.
    private func addStep() {
        editableSteps.append("")
        let index = editableSteps.count - 1
        drafts[index] = ""
        editingSteps.insert(index)
        focusedStep = index
    }

    private func removeStep(at index: Int) {
        guard editableSteps.indices.contains(index) else { return }
        editableSteps.remove(at: index)
        editingSteps = []  // indices shifted
        drafts = [:]
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                onCancel()
            } label: {
                Label("Refaire".tr, systemImage: "arrow.uturn.left")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                Task {
                    await viewModel.confirmAndSubmit(confirmedSteps: nonEmptySteps)
                }
            } label: {
                Label("Soumettre".tr, systemImage: "paperplane.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.phase == .submitting || nonEmptySteps.isEmpty)
        }
        .padding()
    }
}
