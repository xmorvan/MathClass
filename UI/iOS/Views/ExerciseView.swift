//
//  ExerciseView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.11.2024.
//

import SwiftUI
import PencilKit
import UIKit

/// Student-facing exercise view.
/// Top: exercise statement rendered via KaTeX (or image).
/// Middle (60%+): PencilKit drawing canvas.
/// Bottom: Vérifier button → SubmissionViewModel verify → recognize → confirm → submit → feedback flow.
///
/// Owns its own `SubmissionViewModel` as a `@StateObject` so the sheet flow
/// reaches every student. Previously, `submissionVM` was an optional `@State`
/// that was never populated, which made the entire verify→correct path dead
/// code on iOS.
struct ExerciseView: View {
    let exercise: Exercise
    let assignmentMode: AssignmentMode?

    @ObservedObject var studentViewModel: StudentViewModel
    @StateObject private var submissionVM: SubmissionViewModel

    @State private var canvasView = PKCanvasView()
    @State private var hasDrawing = false
    @State private var startTime: Date?
    @State private var showingFlowSheet = false
    @Environment(\.dismiss) var dismiss

    init(
        exercise: Exercise,
        studentViewModel: StudentViewModel,
        assignmentMode: AssignmentMode?
    ) {
        self.exercise = exercise
        self.assignmentMode = assignmentMode
        // ObservedObject wrapper takes the existing instance from the parent.
        self.studentViewModel = studentViewModel
        // StateObject must be constructed exactly once via _submissionVM.
        _submissionVM = StateObject(
            wrappedValue: SubmissionViewModel(
                exercise: exercise,
                assignmentMode: assignmentMode,
                studentViewModel: studentViewModel
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            exerciseHeader
            Divider()
            exerciseContent
            Divider()
            drawingArea
            Divider()
            actionButtons
        }
        .onAppear { startTime = Date() }
        .sheet(isPresented: $showingFlowSheet) {
            submissionFlowSheet(vm: submissionVM)
        }
    }

    // MARK: - Exercise Header

    private var exerciseHeader: some View {
        HStack {
            Text(exercise.title)
                .font(.title2)
                .bold()
            Spacer()
            difficultyStars
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var difficultyStars: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { level in
                Image(systemName: level <= exercise.difficultyLevel ? "star.fill" : "star")
                    .foregroundColor(level <= exercise.difficultyLevel ? .yellow : .gray.opacity(0.3))
                    .font(.system(size: 12))
            }
        }
    }

    // MARK: - Exercise Content (KaTeX + optional image)

    private var exerciseContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !exercise.statement.isEmpty {
                    MathTextView(content: exercise.statement, fontSize: 18)
                        .padding(.horizontal)
                }

                if let imageURL = exercise.statementImageURL, !imageURL.isEmpty {
                    AsyncImageFromStorage(path: imageURL)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 220)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Drawing Area

    private var drawingArea: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Votre travail")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    canvasView.drawing = PKDrawing()
                    hasDrawing = false
                } label: {
                    Label("Effacer", systemImage: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 4)

            CanvasRepresentableiOS(canvasView: $canvasView, hasDrawing: $hasDrawing)
                .frame(minHeight: 300)
                .background(Color.white)
                .cornerRadius(4)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Spacer()

            Button(action: startVerification) {
                Label("Vérifier", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasDrawing)
        }
        .padding()
    }

    // MARK: - Submission Flow Sheet

    @ViewBuilder
    private func submissionFlowSheet(vm: SubmissionViewModel) -> some View {
        NavigationView {
            Group {
                switch vm.phase {
                case .recognizing, .verifying, .submitting:
                    VerificationView(viewModel: vm) {
                        showingFlowSheet = false
                        vm.phase = .drawing
                    }
                case .feedback:
                    FeedbackView(viewModel: vm)
                default:
                    EmptyView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        showingFlowSheet = false
                    }
                }
            }
        }
    }

    // MARK: - Verify (PencilKit → Cloud Function pipeline)

    /// Renders the canvas to a PNG and kicks off the verify → correct flow.
    /// The previous `submitDirectly` legacy path bypassed this entirely and
    /// is gone — there is now a single, well-defined submission pipeline.
    private func startVerification() {
        guard let start = startTime else { return }
        let duration = Date().timeIntervalSince(start)

        let bounds = canvasView.drawing.bounds
        let image = canvasView.drawing.image(from: bounds, scale: 2.0)
        guard let imageData = image.pngData() else { return }

        showingFlowSheet = true
        Task { await submissionVM.verify(imageData: imageData, duration: duration) }
    }
}

/// PencilKit canvas wrapper for iOS.
struct CanvasRepresentableiOS: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var hasDrawing: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(hasDrawing: $hasDrawing)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 5)
        canvasView.backgroundColor = .white
        canvasView.delegate = context.coordinator
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var hasDrawing: Binding<Bool>

        init(hasDrawing: Binding<Bool>) {
            self.hasDrawing = hasDrawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            hasDrawing.wrappedValue = !canvasView.drawing.bounds.isEmpty
        }
    }
}
