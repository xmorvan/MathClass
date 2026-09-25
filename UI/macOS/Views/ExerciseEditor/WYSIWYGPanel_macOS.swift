//
//  WYSIWYGPanel_macOS.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import SwiftUI

/// WYSIWYG creation panel: LaTeX textarea on the left, live KaTeX preview on the right.
/// The teacher types mixed text and LaTeX (using $...$ or $$...$$) in a single textarea.
struct WYSIWYGPanel_macOS: View {
    @ObservedObject var viewModel: ExerciseEditorViewModel

    var body: some View {
        HSplitView {
            editorPane
                .frame(minWidth: 300)
            previewPane
                .frame(minWidth: 250)
        }
    }

    // MARK: - Editor Pane

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Énoncé — LaTeX".tr)

            TextEditor(text: $viewModel.statement)
                .font(.system(.body, design: .monospaced))
                .padding(8)

            Divider()

            sectionLabel("Réponse attendue".tr)

            TextField("ex: x = -3 \\text{ ou } x = 0".tr, text: $viewModel.expectedAnswer)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .padding(8)
        }
    }

    // MARK: - Preview Pane

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Aperçu".tr)

            if viewModel.statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                placeholderView
            } else {
                KaTeXView(
                    content: viewModel.statement,
                    mode: .preview,
                    fontSize: 18,
                    minHeight: 100
                )
            }

            if !viewModel.expectedAnswer.isEmpty {
                Divider()
                sectionLabel("Réponse attendue".tr)
                KaTeXView(
                    content: "$\(viewModel.expectedAnswer)$",
                    mode: .preview,
                    fontSize: 16,
                    minHeight: 40
                )
                .padding(.bottom, 8)
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    private var placeholderView: some View {
        VStack {
            Spacer()
            Text("L'aperçu apparaîtra ici…".tr)
                .foregroundColor(.secondary)
                .italic()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
