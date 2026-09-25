//
//  AssignmentMode.swift
//  MathClass
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import SwiftUI

/// The three assignment modes that determine how students receive exercises and feedback.
///
/// - `differentiation`: Teacher assigns different exercises to different students/groups.
///   Feedback shows which step is wrong. 2nd chance allowed.
/// - `levels`: Students progress automatically through difficulty levels.
///   3 correct first-attempt answers in a row = advance. Feedback is correct/incorrect only.
///   2nd chance allowed but resets the consecutive counter.
/// - `evaluation`: Test mode. No feedback, no 2nd chance. Teacher sees results only.
enum AssignmentMode: String, Codable, Hashable, CaseIterable {
    case differentiation
    case levels
    case evaluation

    /// Localized display name (French)
    var displayName: String {
        switch self {
        case .differentiation: return "Différenciation".tr
        case .levels: return "Niveaux progressifs".tr
        case .evaluation: return "Évaluation".tr
        }
    }

    /// SF Symbol name for this mode
    var iconName: String {
        switch self {
        case .differentiation: return "person.2.fill"
        case .levels: return "chart.bar.fill"
        case .evaluation: return "checkmark.seal.fill"
        }
    }

    /// Display color for this mode
    var color: Color {
        switch self {
        case .differentiation: return .blue
        case .levels: return .orange
        case .evaluation: return .purple
        }
    }

    /// Whether this mode allows a 2nd attempt
    var allows2ndChance: Bool {
        switch self {
        case .differentiation, .levels: return true
        case .evaluation: return false
        }
    }

    /// Whether this mode shows feedback to the student after submission
    var showsFeedback: Bool {
        switch self {
        case .differentiation, .levels: return true
        case .evaluation: return false
        }
    }

    /// Whether this mode shows which specific step is wrong
    var showsErrorStep: Bool {
        switch self {
        case .differentiation: return true
        case .levels, .evaluation: return false
        }
    }
}
