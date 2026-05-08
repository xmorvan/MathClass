//
//  LocalizationManager.swift
//  MathClass
//
//  Bilingual FR/EN runtime localization without .strings files in the
//  build target. Provides an in-app language toggle that takes effect
//  immediately (no app restart). FR is the source-of-truth: keys ARE
//  the French copy already in views; English values are looked up in
//  Localizations.fr2en. Missing keys fall through to themselves so a
//  French user sees French even if a translation is missing.
//

import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Codable {
    case fr
    case en

    var displayName: String {
        switch self {
        case .fr: return "Français"
        case .en: return "English"
        }
    }

    var flag: String {
        switch self {
        case .fr: return "🇫🇷"
        case .en: return "🇬🇧"
        }
    }
}

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    private let storageKey = "MathClass.preferredLanguage"

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: storageKey)
        }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let stored = AppLanguage(rawValue: raw) {
            self.language = stored
        } else {
            let preferred = Locale.preferredLanguages.first ?? "fr"
            self.language = preferred.lowercased().hasPrefix("en") ? .en : .fr
        }
    }

    func string(for key: String) -> String {
        switch language {
        case .fr:
            return key
        case .en:
            return Localizations.fr2en[key] ?? key
        }
    }

    /// Format-style lookup: "Bonjour %@" with arg "Alice" → "Hello Alice".
    func format(_ key: String, _ args: CVarArg...) -> String {
        let template = string(for: key)
        return String(format: template, arguments: args)
    }
}

extension String {
    /// Localized translation — returns the current-language rendering of this
    /// string. The string itself IS the FR key.
    var tr: String {
        LocalizationManager.shared.string(for: self)
    }
}
