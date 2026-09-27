//
//  PlainMathTests.swift
//  MathClassTests
//
//  The keyboard notation students type on the verification screen, and
//  its conversion to and from LaTeX.
//

import XCTest
@testable import MathClass

final class PlainMathTests: XCTestCase {

    // MARK: - Typed → LaTeX

    func testFractions() {
        XCTAssertEqual(PlainMath.toLatex("1/2"), "\\frac{1}{2}")
        XCTAssertEqual(PlainMath.toLatex("(x+1)/2"), "\\frac{x+1}{2}")
        XCTAssertEqual(PlainMath.toLatex("3/(x-2)"), "\\frac{3}{x-2}")
        XCTAssertEqual(PlainMath.toLatex("1/2 + 1/3 = 5/6"), "\\frac{1}{2} + \\frac{1}{3} = \\frac{5}{6}")
        XCTAssertEqual(PlainMath.toLatex("0,12/0,4 = 0,3"), "\\frac{0,12}{0,4} = 0,3")
    }

    func testPowersRootsAndSymbols() {
        XCTAssertEqual(PlainMath.toLatex("x^2 - 9"), "x^{2} - 9")
        XCTAssertEqual(PlainMath.toLatex("2^(n+1)"), "2^{n+1}")
        XCTAssertEqual(PlainMath.toLatex("e^-x"), "e^{-x}")
        XCTAssertEqual(PlainMath.toLatex("√(x+1)"), "\\sqrt{x+1}")
        XCTAssertEqual(PlainMath.toLatex("√100 = 10"), "\\sqrt{100} = 10")
        XCTAssertEqual(PlainMath.toLatex("3 × 4 = 12"), "3 \\times 4 = 12")
        XCTAssertEqual(PlainMath.toLatex("3*4"), "3 \\times 4")
        XCTAssertEqual(PlainMath.toLatex("x ≤ 5"), "x \\leq 5")
        XCTAssertEqual(PlainMath.toLatex("2π"), "2\\pi")
        XCTAssertEqual(PlainMath.toLatex("x = 5π/6"), "x = \\frac{5\\pi}{6}")
        XCTAssertEqual(PlainMath.toLatex("u_10 = 35"), "u_{10} = 35")
    }

    func testWordsAndFunctions() {
        XCTAssertEqual(PlainMath.toLatex("x = 2 ou x = 3"), "x = 2 \\text{ ou } x = 3")
        XCTAssertEqual(PlainMath.toLatex("2500 m"), "2500 m")
        XCTAssertEqual(PlainMath.toLatex("10 cm"), "10 \\text{ cm }")
        XCTAssertEqual(PlainMath.toLatex("sin(x) = 1/2"), "\\sin(x) = \\frac{1}{2}")
        XCTAssertEqual(PlainMath.toLatex("2xy + 1"), "2xy + 1")
    }

    // MARK: - LaTeX → shown to the student

    func testLatexIsShownWithoutCommands() {
        XCTAssertEqual(PlainMath.fromLatex("\\frac{1}{2}"), "1/2")
        XCTAssertEqual(PlainMath.fromLatex("\\frac{x+1}{2}"), "(x+1)/2")
        XCTAssertEqual(PlainMath.fromLatex("\\sqrt{2}"), "√2")
        XCTAssertEqual(PlainMath.fromLatex("\\sqrt{x+1}"), "√(x+1)")
        XCTAssertEqual(PlainMath.fromLatex("x^{2} - 4x"), "x^2 - 4x")
        XCTAssertEqual(PlainMath.fromLatex("2^{n+1}"), "2^(n+1)")
        XCTAssertEqual(PlainMath.fromLatex("6 \\times 7 = 42"), "6 × 7 = 42")
        XCTAssertEqual(PlainMath.fromLatex("x \\leq 5"), "x ≤ 5")
        XCTAssertEqual(PlainMath.fromLatex("x = 2 \\text{ ou } x = 3"), "x = 2 ou x = 3")
        XCTAssertEqual(PlainMath.fromLatex("\\left(x+1\\right)^{2}"), "(x+1)^2")
        XCTAssertEqual(PlainMath.fromLatex("\\cos\\left(\\frac{\\pi}{3}\\right)"), "cos(π/3)")
    }

    // MARK: - Round trip

    /// A recognised line the student opens and leaves as it is must come
    /// back as the same maths.
    func testRoundTripKeepsTheMaths() {
        let lines = [
            "\\frac{3}{6} + \\frac{2}{6} = \\frac{5}{6}",
            "x^{2} - 9 = (x - 3)(x + 3)",
            "\\sqrt{100} = 10",
            "x = \\frac{\\pi}{6} \\text{ ou } x = \\frac{5 \\pi}{6}",
            "6 \\times 7 = 42",
            "f'(x) = 3x^{2} - 4",
        ]
        for line in lines {
            let back = PlainMath.toLatex(PlainMath.fromLatex(line))
            XCTAssertEqual(back.replacingOccurrences(of: " ", with: ""), line.replacingOccurrences(of: " ", with: ""), line)
        }
    }
}
