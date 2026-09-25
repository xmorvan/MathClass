//
//  NotationNoteTests.swift
//  MathClassTests
//
//  Verifies that every key the Cloud Function may return resolves to a
//  non-empty localized phrase. If a future correct_submission.py adds a
//  new NOTATION_KEYS entry, this test fails the build until the iOS
//  client maps it (ISSUE-014 §1.6 contract guard).
//

import XCTest
@testable import MathClass

final class NotationNoteTests: XCTestCase {

    /// Mirrors `NOTATION_KEYS` in functions/correct_submission.py. Keep in
    /// sync; the test guards against drift.
    private static let knownKeys: [String] = [
        "missing_brackets",
        "decimal_separator",
        "implicit_multiplication",
        "missing_unit",
        "ambiguous_fraction",
        "power_notation",
    ]

    func testEveryServerKeyMapsToANonEmptyPhrase() {
        for key in Self.knownKeys {
            let message = NotationNote.localizedMessage(forKey: key)
            XCTAssertFalse(
                message.isEmpty,
                "Notation note key '\(key)' fell through to an empty string. " +
                "Update NotationNote.localizedMessage(forKey:) in Submission.swift."
            )
        }
    }

    func testUnknownKeyReturnsEmpty() {
        // Unknown keys should not crash and should yield an empty string
        // so the FeedbackView banner stays hidden.
        XCTAssertEqual(NotationNote.localizedMessage(forKey: "not_a_real_key"), "")
        XCTAssertEqual(NotationNote.localizedMessage(forKey: ""), "")
    }
}
