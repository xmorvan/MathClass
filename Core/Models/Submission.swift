//
//  Submission.swift
//  MathClass
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import FirebaseFirestore

/// A student's submission for a specific exercise within an assignment.
/// Stored in Firestore at `submissions/{submissionID}`.
struct Submission: Identifiable, Codable {
    @DocumentID var id: String?
    var studentID: String
    var exerciseID: String
    var assignmentID: String
    /// 1 for first attempt, 2 for second attempt (2nd chance)
    var attemptNumber: Int
    /// Cloud Storage path to the raw PencilKit drawing data
    var inkDataRef: String?
    /// Cloud Storage URL to the PNG export of the student's handwriting
    var pngURL: String?
    /// The LaTeX steps extracted from handwriting recognition (confirmed by student)
    var latexSteps: [String]
    /// The correction result from the hybrid Claude + SymPy pipeline
    var correctionResult: CorrectionResult?
    /// The final outcome of this submission
    var finalResult: SubmissionResult?
    /// Time the student spent on this exercise, in seconds
    var timeSpent: TimeInterval
    /// When the submission was created
    var timestamp: Date

    init(
        id: String? = nil,
        studentID: String,
        exerciseID: String,
        assignmentID: String,
        attemptNumber: Int = 1,
        inkDataRef: String? = nil,
        pngURL: String? = nil,
        latexSteps: [String] = [],
        correctionResult: CorrectionResult? = nil,
        finalResult: SubmissionResult? = nil,
        timeSpent: TimeInterval = 0,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.studentID = studentID
        self.exerciseID = exerciseID
        self.assignmentID = assignmentID
        self.attemptNumber = attemptNumber
        self.inkDataRef = inkDataRef
        self.pngURL = pngURL
        self.latexSteps = latexSteps
        self.correctionResult = correctionResult
        self.finalResult = finalResult
        self.timeSpent = timeSpent
        self.timestamp = timestamp
    }
}

// MARK: - Correction Result

/// The result of the hybrid correction pipeline (Claude + SymPy).
struct CorrectionResult: Codable, Hashable {
    /// Per-step boolean: true = correct, false = incorrect
    var stepResults: [Bool]
    /// Index of the first incorrect step (nil if all steps are correct)
    var firstErrorIndex: Int?
    /// Optional language-neutral notation-issue key (e.g. `missing_brackets`,
    /// `decimal_separator`). Populated when the parent class has
    /// `notationStrict == true` and the math is correct but the notation
    /// is sloppy. Never flips `stepResults` to false — notation is always
    /// non-blocking. The iOS client renders a localized banner via
    /// `Localizations.swift` keyed on `notation_note_<key>`.
    var notationNoteKey: String?
    /// Optional per-step error categories (e.g. "sign_error", "arithmetic",
    /// "notation"). Same length as `stepResults`. `nil` for steps that
    /// are correct or don't fit a known category.
    var errorTags: [String?]?

    init(
        stepResults: [Bool],
        firstErrorIndex: Int? = nil,
        notationNoteKey: String? = nil,
        errorTags: [String?]? = nil
    ) {
        self.stepResults = stepResults
        self.firstErrorIndex = firstErrorIndex
        self.notationNoteKey = notationNoteKey
        self.errorTags = errorTags
    }
}

// MARK: - Notation note key → localized message

/// Maps the Cloud Function's language-neutral notation-note keys to a
/// localized phrase. The function returns one of these keys (see
/// `NOTATION_KEYS` in `functions/correct_submission.py`); the iOS view
/// renders the result of `localizedMessage(forKey:)`.
enum NotationNote {
    static func localizedMessage(forKey key: String) -> String {
        switch key {
        case "missing_brackets":
            return "Pensez à mettre les négatifs entre parenthèses, par exemple (-3) plutôt que -3.".tr
        case "decimal_separator":
            return "Choisissez la virgule ou le point pour les décimaux et restez cohérent.".tr
        case "implicit_multiplication":
            return "Notez explicitement la multiplication, par exemple 2·x au lieu de 2x.".tr
        case "missing_unit":
            return "Pensez à indiquer l'unité dans la réponse.".tr
        case "ambiguous_fraction":
            return "Mettez les parenthèses autour des fractions ambiguës (par exemple (1/2)x).".tr
        case "power_notation":
            return "Utilisez x^2 plutôt que xx pour les puissances.".tr
        default:
            return ""
        }
    }
}

// MARK: - Submission Result

/// The final outcome of a submission attempt.
enum SubmissionResult: String, Codable, Hashable {
    /// Correct on the first attempt
    case success1st = "success_1st"
    /// Correct on the second attempt (2nd chance)
    case success2nd = "success_2nd"
    /// Incorrect on all allowed attempts
    case failed = "failed"

    /// Localized display name (French)
    var displayName: String {
        switch self {
        case .success1st: return String(localized: "Réussi (1er essai)")
        case .success2nd: return String(localized: "Réussi (2e essai)")
        case .failed: return String(localized: "Échoué")
        }
    }

    /// Whether this result counts as a success
    var isSuccess: Bool {
        switch self {
        case .success1st, .success2nd: return true
        case .failed: return false
        }
    }
}
