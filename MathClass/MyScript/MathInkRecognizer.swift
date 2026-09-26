//
//  MathInkRecognizer.swift
//  MathClass (iPad)
//
//  On-device handwriting recognition of maths with MyScript iink: the
//  student's PencilKit strokes are split into lines and each line is turned
//  into LaTeX, fast enough to show while the student writes. Nothing leaves
//  the iPad.
//

import PencilKit
import Foundation
import libiink

/// One written line and what MyScript read in it.
struct RecognizedInkLine: Equatable {
    let latex: String
    /// Vertical extent of the line's ink, in canvas points.
    let minY: CGFloat
    let maxY: CGFloat
}

/// Recognises a PencilKit drawing as one LaTeX expression per written line.
final class MathInkRecognizer {

    static let shared = MathInkRecognizer()

    /// Why recognition is unavailable (missing certificate or assets), or
    /// nil when the engine is ready.
    private(set) var unavailableReason: String?

    /// iink objects are used from this queue only.
    private let queue = DispatchQueue(label: "MathInkRecognizer")
    private var engine: IINKEngine?
    private var recognizer: IINKRecognizer?

    /// PencilKit works in points; iink wants millimetres. An iPad point is
    /// about 1/132 inch on screen.
    private let millimetresPerPoint: Float = 25.4 / 132

    /// Vertical gap (points) between two groups of strokes that starts a new
    /// line. Fraction bars, exponents and indices sit much closer.
    private let lineGap: CGFloat = 28

    private init() {
        queue.sync { setUp() }
        if let unavailableReason {
            print("MathInkRecognizer unavailable: \(unavailableReason)")
        }
    }

    var isAvailable: Bool { unavailableReason == nil }

    // MARK: - Recognition

    /// Each written line, top to bottom, with its LaTeX. Lines MyScript
    /// could not read are dropped.
    func recognizeLines(in drawing: PKDrawing) async -> [RecognizedInkLine] {
        let lines = Self.splitIntoLines(drawing.strokes, gap: lineGap)
        return await withCheckedContinuation { continuation in
            queue.async {
                let results: [RecognizedInkLine] = lines.compactMap { strokes in
                    guard let latex = self.recognize(strokes: strokes) else { return nil }
                    let bounds = strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
                    return RecognizedInkLine(latex: latex, minY: bounds.minY, maxY: bounds.maxY)
                }
                continuation.resume(returning: results)
            }
        }
    }

    private func recognize(strokes: [PKStroke]) -> String? {
        guard let recognizer else { return nil }
        do {
            try recognizer.clear()
            var events: [IINKPointerEvent] = []
            var pointerTime: Int64 = 0
            for stroke in strokes {
                let points = Array(stroke.path)
                guard !points.isEmpty else { continue }
                for (index, point) in points.enumerated() {
                    let location = point.location.applying(stroke.transform)
                    let type: IINKPointerEventType = index == 0
                        ? .down
                        : (index == points.count - 1 ? .up : .move)
                    events.append(IINKPointerEventMake(
                        type, location, pointerTime, Float(point.force), .pen, 0
                    ))
                    pointerTime += 8
                }
                if points.count == 1, let point = points.first {
                    events.append(IINKPointerEventMake(
                        .up, point.location.applying(stroke.transform), pointerTime, Float(point.force), .pen, 0
                    ))
                }
                pointerTime += 120
            }
            guard !events.isEmpty else { return nil }
            try events.withUnsafeMutableBufferPointer { buffer in
                try recognizer.pointerEvents(buffer.baseAddress!, count: buffer.count)
            }
            recognizer.waitForIdle()
            let latex = Self.tidy(try recognizer.result(mimeType: .laTeX))
            return latex.isEmpty ? nil : latex
        } catch {
            print("MathInkRecognizer: \(error.localizedDescription)")
            return nil
        }
    }

    /// MyScript separates every token with a space ("1 4" for 14), which
    /// the correction would read as 1 × 4: join digits, trim the rest.
    static func tidy(_ latex: String) -> String {
        latex
            .replacingOccurrences(of: #"(?<=[0-9])\s+(?=[0-9.,])|(?<=[.,])\s+(?=[0-9])"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Lines

    /// Groups strokes whose vertical extents are closer than `gap`.
    static func splitIntoLines(_ strokes: [PKStroke], gap: CGFloat) -> [[PKStroke]] {
        let sorted = strokes
            .filter { !$0.renderBounds.isNull && !$0.renderBounds.isEmpty }
            .sorted { $0.renderBounds.minY < $1.renderBounds.minY }
        var lines: [(maxY: CGFloat, strokes: [PKStroke])] = []
        for stroke in sorted {
            let bounds = stroke.renderBounds
            if let last = lines.last, bounds.minY <= last.maxY + gap {
                lines[lines.count - 1].strokes.append(stroke)
                lines[lines.count - 1].maxY = max(last.maxY, bounds.maxY)
            } else {
                lines.append((bounds.maxY, [stroke]))
            }
        }
        return lines.map { line in line.strokes.sorted { $0.renderBounds.minX < $1.renderBounds.minX } }
    }

    // MARK: - Engine

    private func setUp() {
        guard myCertificate.length > 0 else {
            unavailableReason = "Certificat MyScript absent"
            return
        }
        let certificate = Data(bytes: myCertificate.bytes, count: myCertificate.length)
        guard let engine = IINKEngine(certificate: certificate) else {
            unavailableReason = "Certificat MyScript invalide"
            return
        }
        guard let resourcePath = Bundle.main.resourcePath else {
            unavailableReason = "Ressources introuvables"
            return
        }
        let configurationPath = resourcePath + "/MyScriptAssets.bundle/recognition-assets/conf"
        guard FileManager.default.fileExists(atPath: configurationPath) else {
            unavailableReason = "Ressources de reconnaissance MyScript absentes"
            return
        }
        do {
            try engine.configuration.set(stringArray: [configurationPath], forKey: "recognizer.configuration-manager.search-path")
            try engine.configuration.set(string: "math2", forKey: "recognizer.math.configuration.bundle")
            try engine.configuration.set(string: "standard", forKey: "recognizer.math.configuration.name")
            try engine.configuration.set(string: NSTemporaryDirectory(), forKey: "content-package.temp-folder")
            recognizer = try engine.createRecognizer(scaleX: millimetresPerPoint, scaleY: millimetresPerPoint, type: "Math")
            self.engine = engine
        } catch {
            unavailableReason = "MyScript : \(error.localizedDescription)"
        }
    }
}
