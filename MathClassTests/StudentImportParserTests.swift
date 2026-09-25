//
//  StudentImportParserTests.swift
//  MathClassTests
//
//  Pure-logic tests for the paste/CSV student-roster parser. No Firebase,
//  no SwiftUI — runs in milliseconds. Pulled out as the first concrete
//  step toward §4.E.2's "no Swift unit tests" gap; once a test target
//  exists in the Xcode project, this file is auto-included via the
//  PBXFileSystemSynchronizedRootGroup pattern used elsewhere.
//

import XCTest
@testable import MathClass

final class StudentImportParserTests: XCTestCase {

    func testParseTabSeparatedWithoutHeader() {
        let text = """
        Alice\tDémo
        Bob\tDupont
        """
        let students = StudentImportParser.parse(text)
        XCTAssertEqual(students.count, 2)
        XCTAssertEqual(students[0].firstName, "Alice")
        XCTAssertEqual(students[0].lastName, "Démo")
        XCTAssertEqual(students[1].firstName, "Bob")
        XCTAssertEqual(students[1].lastName, "Dupont")
    }

    func testParseCommaSeparatedWithHeader() {
        // Header in French puts last name first → parser flips order.
        let text = """
        nom,prénom
        Démo,Alice
        Dupont,Bob
        """
        let students = StudentImportParser.parse(text)
        XCTAssertEqual(students.count, 2)
        XCTAssertEqual(students[0].firstName, "Alice")
        XCTAssertEqual(students[0].lastName, "Démo")
    }

    func testParseSemicolonSeparated() {
        let text = "Alice;Démo\nBob;Dupont"
        let students = StudentImportParser.parse(text)
        XCTAssertEqual(students.count, 2)
        XCTAssertEqual(students[0].lastName, "Démo")
    }

    func testParseSpaceSeparated() {
        let text = "Alice Démo\nBob Dupont"
        let students = StudentImportParser.parse(text)
        XCTAssertEqual(students.count, 2)
        XCTAssertEqual(students[0].firstName, "Alice")
        XCTAssertEqual(students[1].firstName, "Bob")
    }

    func testEmptyTextReturnsEmpty() {
        XCTAssertEqual(StudentImportParser.parse("").count, 0)
        XCTAssertEqual(StudentImportParser.parse("   \n\t").count, 0)
    }

    func testSingleColumnLinesAreSkipped() {
        // No separator → can't infer last/first → row is dropped.
        let text = "Alice\nBob Dupont"
        let students = StudentImportParser.parse(text)
        XCTAssertEqual(students.count, 1)
        XCTAssertEqual(students[0].firstName, "Bob")
    }

    func testMultiWordLastNamePreserved() {
        let text = "Alice\tEl Amrani"
        let students = StudentImportParser.parse(text)
        XCTAssertEqual(students.count, 1)
        XCTAssertEqual(students[0].lastName, "El Amrani")
    }

    func testHeaderAloneProducesNoStudents() {
        let text = "nom,prénom"
        XCTAssertEqual(StudentImportParser.parse(text).count, 0)
    }
}
