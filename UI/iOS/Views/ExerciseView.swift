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
    @State private var isErasing: Bool = false
    /// Bumped on every stroke change; drives the live recognition.
    @State private var drawingVersion: Int = 0
    /// What MyScript reads, line by line, while the student writes.
    @State private var liveLines: [RecognizedInkLine] = []
    private let inkRecognizer = MathInkRecognizer.shared
    @State private var statementHeight: CGFloat = 0
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
        // Full-width band that is only as tall as the statement (up to
        // 220 pt, then it scrolls), leaving the rest to the drawing area.
        ScrollView {
            statementStack
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(key: StatementHeightKey.self, value: geometry.size.height)
                    }
                )
        }
        .frame(height: min(max(statementHeight, 44), 220))
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
        .onPreferenceChange(StatementHeightKey.self) { statementHeight = $0 }
    }

    private var statementStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !exercise.statement.isEmpty {
                // The native renderer only styles $…$; fractions, powers and
                // other commands need KaTeX, or the student reads raw LaTeX.
                if exercise.statement.contains("\\") {
                    KaTeXView(content: exercise.statement, mode: .preview, fontSize: 20, minHeight: 90)
                        .frame(height: 90)
                        .padding(.horizontal)
                } else {
                    MathTextView(content: exercise.statement, fontSize: 20)
                        .padding(.horizontal)
                }
            }

            if let imageURL = exercise.statementImageURL, !imageURL.isEmpty {
                AsyncImageFromStorage(path: imageURL)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Drawing Area

    private var drawingArea: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Votre travail".tr)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                // Pen / eraser: an Apple Pencil double-tap also switches.
                Picker("Outil".tr, selection: $isErasing) {
                    Label("Stylo".tr, systemImage: "pencil.tip").tag(false)
                    Label("Gomme".tr, systemImage: "eraser").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                Button {
                    canvasView.undoManager?.undo()
                    hasDrawing = !canvasView.drawing.bounds.isEmpty
                } label: {
                    Label("Annuler le trait".tr, systemImage: "arrow.uturn.backward")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                Button {
                    canvasView.drawing = PKDrawing()
                    hasDrawing = false
                    isErasing = false
                } label: {
                    Label("Effacer".tr, systemImage: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 4)

            HStack(spacing: 0) {
                CanvasRepresentableiOS(
                    canvasView: $canvasView,
                    hasDrawing: $hasDrawing,
                    isErasing: $isErasing,
                    drawingVersion: $drawingVersion
                )
                .frame(minHeight: 300)
                .background(RuledPaper())
                .cornerRadius(4)

                if inkRecognizer.isAvailable {
                    liveReadingColumn
                        .frame(width: 280)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        // Read the ink a moment after the student stops writing; a new
        // stroke cancels the pending reading.
        .task(id: drawingVersion) {
            guard inkRecognizer.isAvailable else { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let lines = await inkRecognizer.recognizeLines(in: canvasView.drawing)
            guard !Task.isCancelled else { return }
            liveLines = lines
        }
    }

    /// Each line as the app reads it, rendered as maths and placed at the
    /// height of the ink, so the student can rewrite what was misread.
    private var liveReadingColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ce que l'app lit".tr)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 6)
            if liveLines.isEmpty {
                Text("Écrivez une étape par ligne : ce que l'app lit s'affiche ici, en face de votre écriture.".tr)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
            }
            GeometryReader { _ in
                ZStack(alignment: .topLeading) {
                    ForEach(Array(liveLines.enumerated()), id: \.offset) { _, line in
                        KaTeXView(content: "$\(line.latex)$", mode: .preview, fontSize: 20, minHeight: 36)
                            .frame(height: max(36, line.maxY - line.minY))
                            .offset(y: max(0, line.minY - 24))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            }
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(4)
        .padding(.leading, 8)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Spacer()

            Button(action: startVerification) {
                Label("Vérifier".tr, systemImage: "checkmark.seal.fill")
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
                    Button("Fermer".tr) {
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

        guard let imageData = renderCanvasPNG(canvasView: canvasView) else { return }

        showingFlowSheet = true
        let drawing = canvasView.drawing
        Task {
            // Lines read on the iPad make the cloud recognition unnecessary.
            let onDeviceSteps = inkRecognizer.isAvailable
                ? await inkRecognizer.recognizeLines(in: drawing).map(\.latex)
                : []
            await submissionVM.verify(imageData: imageData, duration: duration, onDeviceSteps: onDeviceSteps)
        }
    }

    /// Render the PencilKit drawing to a PNG sized for upload + recognition.
    ///
    /// On a 12.9" iPad Pro, the previous `scale: 2.0` rendering produced
    /// 5–10 MB images that strained the recognize_handwriting upload and
    /// burned the Cloud Function timeout (ISSUE-009). We now render at 1×
    /// and downscale further if the long edge exceeds `maxLongEdge` so the
    /// payload is consistently in the hundreds-of-KB range.
    private func renderCanvasPNG(canvasView: PKCanvasView) -> Data? {
        let bounds = canvasView.drawing.bounds
        guard !bounds.isEmpty else { return nil }

        let maxLongEdge: CGFloat = 1600
        let longEdge = max(bounds.width, bounds.height)
        let scale: CGFloat = longEdge > maxLongEdge ? (maxLongEdge / longEdge) : 1.0

        let image = canvasView.drawing.image(from: bounds, scale: scale)
        return image.pngData()
    }
}

/// PencilKit canvas wrapper for iOS.
struct CanvasRepresentableiOS: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var hasDrawing: Bool
    @Binding var isErasing: Bool
    @Binding var drawingVersion: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(hasDrawing: $hasDrawing, isErasing: $isErasing, drawingVersion: $drawingVersion)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = Self.tool(erasing: isErasing)
        // Transparent so the ruled paper behind shows through.
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.delegate = context.coordinator
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        canvasView.addInteraction(pencilInteraction)
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.tool = Self.tool(erasing: isErasing)
    }

    static func tool(erasing: Bool) -> PKTool {
        erasing ? PKEraserTool(.vector) : PKInkingTool(.pen, color: .black, width: 5)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var hasDrawing: Binding<Bool>
        var isErasing: Binding<Bool>
        var drawingVersion: Binding<Int>

        init(hasDrawing: Binding<Bool>, isErasing: Binding<Bool>, drawingVersion: Binding<Int>) {
            self.hasDrawing = hasDrawing
            self.isErasing = isErasing
            self.drawingVersion = drawingVersion
        }

        /// Apple Pencil double-tap switches between pen and eraser.
        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            isErasing.wrappedValue.toggle()
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            hasDrawing.wrappedValue = !canvasView.drawing.bounds.isEmpty
            drawingVersion.wrappedValue += 1
        }
    }
}

// MARK: - Statement height

private struct StatementHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Ruled paper

/// Faint writing lines, one step per line: students write more legibly and
/// the live reading separates the lines more reliably.
private struct RuledPaper: View {
    var spacing: CGFloat = 90

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = spacing
            while y < size.height {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(Color.blue.opacity(0.12)), lineWidth: 1)
                y += spacing
            }
        }
        .background(Color.white)
    }
}
