//
//  InlineHint.swift
//  MathClass-Shared
//
//  Lightweight one-line hint component placed directly under a control
//  to explain its purpose to a teacher who has never seen the app
//  before. Used as the canonical reusable form for ad-hoc captions
//  scattered across views (e.g. VerificationView and the Statistics
//  detail panes).
//

import SwiftUI

/// Compact "explanatory sentence near a control" affordance. Defaults
/// to subtle styling that doesn't compete with the primary text.
public struct InlineHint: View {
    private let message: String
    private let icon: String?

    /// - Parameters:
    ///   - message: A short sentence (≤ 1–2 lines). The view applies `.tr`
    ///     so the caller passes the FR copy as the key.
    ///   - icon: Optional SF Symbol name, e.g. "info.circle".
    public init(_ message: String, icon: String? = nil) {
        self.message = message
        self.icon = icon
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(message.tr)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
