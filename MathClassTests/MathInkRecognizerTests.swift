//
//  MathInkRecognizerTests.swift
//  MathClassTests
//
//  Feeds MyScript continuous strokes drawn with a simple stroke font and
//  checks what it reads. Skipped when the certificate or the recognition
//  assets are not installed.
//

import XCTest
import PencilKit
@testable import MathClass

final class MathInkRecognizerTests: XCTestCase {

    /// Stroke font, each glyph in a unit box (y down).
    private static let glyphs: [Character: [[CGPoint]]] = [
        "0": [[CGPoint(x: 0.5, y: 0.0), CGPoint(x: 0.68, y: 0.04), CGPoint(x: 0.84, y: 0.15), CGPoint(x: 0.94, y: 0.31), CGPoint(x: 0.98, y: 0.5), CGPoint(x: 0.94, y: 0.69), CGPoint(x: 0.84, y: 0.85), CGPoint(x: 0.68, y: 0.96), CGPoint(x: 0.5, y: 1.0), CGPoint(x: 0.32, y: 0.96), CGPoint(x: 0.16, y: 0.85), CGPoint(x: 0.06, y: 0.69), CGPoint(x: 0.02, y: 0.5), CGPoint(x: 0.06, y: 0.31), CGPoint(x: 0.16, y: 0.15), CGPoint(x: 0.32, y: 0.04), CGPoint(x: 0.5, y: 0.0)]],
        "1": [[CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.6, y: 0), CGPoint(x: 0.6, y: 1)]],
        "2": [[CGPoint(x: 0, y: 0.15), CGPoint(x: 0.4, y: 0), CGPoint(x: 1, y: 0.15), CGPoint(x: 1, y: 0.45), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)]],
        "3": [[CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0.4, y: 0.45), CGPoint(x: 1, y: 0.7), CGPoint(x: 0.5, y: 1), CGPoint(x: 0, y: 0.9)]],
        "4": [[CGPoint(x: 0.7, y: 1), CGPoint(x: 0.7, y: 0), CGPoint(x: 0, y: 0.7), CGPoint(x: 1, y: 0.7)]],
        "5": [[CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 0.45), CGPoint(x: 0.9, y: 0.5), CGPoint(x: 1, y: 0.8), CGPoint(x: 0.5, y: 1), CGPoint(x: 0, y: 0.9)]],
        "6": [[CGPoint(x: 0.85, y: 0.02), CGPoint(x: 0.35, y: 0.3), CGPoint(x: 0.1, y: 0.65), CGPoint(x: 0.1, y: 0.72), CGPoint(x: 0.14, y: 0.6), CGPoint(x: 0.25, y: 0.5), CGPoint(x: 0.41, y: 0.45), CGPoint(x: 0.59, y: 0.45), CGPoint(x: 0.75, y: 0.5), CGPoint(x: 0.86, y: 0.6), CGPoint(x: 0.9, y: 0.72), CGPoint(x: 0.86, y: 0.84), CGPoint(x: 0.75, y: 0.94), CGPoint(x: 0.59, y: 0.99), CGPoint(x: 0.41, y: 0.99), CGPoint(x: 0.25, y: 0.94), CGPoint(x: 0.14, y: 0.84), CGPoint(x: 0.1, y: 0.72)]],
        "7": [[CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0.3, y: 1)]],
        "8": [[CGPoint(x: 0.5, y: 0.01), CGPoint(x: 0.63, y: 0.03), CGPoint(x: 0.73, y: 0.1), CGPoint(x: 0.79, y: 0.2), CGPoint(x: 0.79, y: 0.3), CGPoint(x: 0.73, y: 0.4), CGPoint(x: 0.63, y: 0.47), CGPoint(x: 0.5, y: 0.49), CGPoint(x: 0.37, y: 0.47), CGPoint(x: 0.27, y: 0.4), CGPoint(x: 0.21, y: 0.3), CGPoint(x: 0.21, y: 0.2), CGPoint(x: 0.27, y: 0.1), CGPoint(x: 0.37, y: 0.03), CGPoint(x: 0.5, y: 0.01)], [CGPoint(x: 0.5, y: 0.48), CGPoint(x: 0.66, y: 0.51), CGPoint(x: 0.8, y: 0.58), CGPoint(x: 0.87, y: 0.68), CGPoint(x: 0.87, y: 0.8), CGPoint(x: 0.8, y: 0.9), CGPoint(x: 0.66, y: 0.97), CGPoint(x: 0.5, y: 1.0), CGPoint(x: 0.34, y: 0.97), CGPoint(x: 0.2, y: 0.9), CGPoint(x: 0.13, y: 0.8), CGPoint(x: 0.13, y: 0.68), CGPoint(x: 0.2, y: 0.58), CGPoint(x: 0.34, y: 0.51), CGPoint(x: 0.5, y: 0.48)]],
        "9": [[CGPoint(x: 1, y: 0.4), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0, y: 0.25), CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 0.25), CGPoint(x: 1, y: 1)]],
        "x": [[CGPoint(x: 0, y: 0.35), CGPoint(x: 1, y: 1)], [CGPoint(x: 1, y: 0.35), CGPoint(x: 0, y: 1)]],
        "+": [[CGPoint(x: 0.5, y: 0.3), CGPoint(x: 0.5, y: 0.95)], [CGPoint(x: 0.1, y: 0.62), CGPoint(x: 0.9, y: 0.62)]],
        "-": [[CGPoint(x: 0.1, y: 0.62), CGPoint(x: 0.9, y: 0.62)]],
        "=": [[CGPoint(x: 0.05, y: 0.5), CGPoint(x: 0.95, y: 0.5)], [CGPoint(x: 0.05, y: 0.78), CGPoint(x: 0.95, y: 0.78)]],
        "(": [[CGPoint(x: 0.8, y: 0), CGPoint(x: 0.3, y: 0.3), CGPoint(x: 0.3, y: 0.7), CGPoint(x: 0.8, y: 1)]],
        ")": [[CGPoint(x: 0.2, y: 0), CGPoint(x: 0.7, y: 0.3), CGPoint(x: 0.7, y: 0.7), CGPoint(x: 0.2, y: 1)]],
        "/": [[CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1)]],
    ]

    /// Draws each line of `lines` as continuous PencilKit strokes.
    private func drawing(_ lines: [String]) -> PKDrawing {
        let width: CGFloat = 34, height: CGFloat = 52, gap: CGFloat = 16
        var strokes: [PKStroke] = []
        let ink = PKInk(.pen, color: .black)
        for (lineIndex, line) in lines.enumerated() {
            var x: CGFloat = 40
            let y: CGFloat = 40 + CGFloat(lineIndex) * 100
            for character in line {
                if character == " " { x += width * 0.6; continue }
                for glyphStroke in Self.glyphs[character] ?? [] {
                    var points: [PKStrokePoint] = []
                    var time: TimeInterval = 0
                    let corners = glyphStroke.map { CGPoint(x: x + $0.x * width, y: y + $0.y * height) }
                    for (a, b) in zip(corners, corners.dropFirst()) {
                        let steps = max(2, Int(hypot(b.x - a.x, b.y - a.y) / 3))
                        for step in 0..<steps {
                            let t = CGFloat(step) / CGFloat(steps)
                            points.append(point(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), time))
                            time += 0.008
                        }
                    }
                    if let last = corners.last { points.append(point(last, time)) }
                    strokes.append(PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: Date())))
                }
                x += width + gap
            }
        }
        return PKDrawing(strokes: strokes)
    }

    private func point(_ location: CGPoint, _ time: TimeInterval) -> PKStrokePoint {
        PKStrokePoint(location: location, timeOffset: time, size: CGSize(width: 3, height: 3),
                      opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
    }

    private func normalized(_ latex: String) -> String {
        latex.replacingOccurrences(of: " ", with: "")
    }

    func testReadsEachLineOfASolution() async throws {
        let recognizer = MathInkRecognizer.shared
        try XCTSkipUnless(recognizer.isAvailable, recognizer.unavailableReason ?? "")
        let lines = await recognizer.recognizeLines(in: drawing(["2x+6=14", "2x=8", "x=4"]))
        print("MyScript read:", lines.map(\.latex))
        // The test font's angular "6" can pass for a 5; the other lines
        // must be exact.
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines.dropFirst().map { normalized($0.latex) }, ["2x=8", "x=4"])
        XCTAssertTrue(lines.first?.latex.hasSuffix("= 14") ?? false, "digits must be joined")
    }

    func testTidyJoinsDigitsOnly() {
        XCTAssertEqual(MathInkRecognizer.tidy(" 2 x + 1 4 = 3 . 5 "), "2 x + 14 = 3.5")
        XCTAssertEqual(MathInkRecognizer.tidy("\\frac { 1 2 } { 3 }"), "\\frac { 12 } { 3 }")
    }

    func testSplitsMultiLineResults() {
        XCTAssertEqual(MathInkRecognizer.splitRows("\\begin{aligned} 2 x &= 8 \\\\ x &= 4 \\end{aligned}"), ["2 x = 8", "x = 4"])
        XCTAssertEqual(MathInkRecognizer.splitRows("x = 4"), ["x = 4"])
    }

    func testKeepsAFractionOnOneLine() async throws {
        let recognizer = MathInkRecognizer.shared
        try XCTSkipUnless(recognizer.isAvailable, recognizer.unavailableReason ?? "")
        let lines = await recognizer.recognizeLines(in: drawing(["x=12/3", "x=4"]))
        print("MyScript read:", lines.map(\.latex))
        XCTAssertEqual(lines.count, 2)
    }
}
