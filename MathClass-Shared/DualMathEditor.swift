//
//  DualMathEditor.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import SwiftUI

/// A dual-mode math editor with LaTeX textarea input and live KaTeX preview.
/// Replaces the old MathLive-based DualMathEditor.
///
/// This is now a thin wrapper around KaTeXView in editor mode.
/// Kept for backward compatibility with any views still referencing DualMathEditor.
struct DualMathEditor: View {
    /// The LaTeX content to edit.
    @Binding var latex: String

    /// Font size for the editor.
    var fontSize: CGFloat = 16

    /// Optional error handler (maintained for API compatibility).
    var onError: ((String) -> Void)?

    var body: some View {
        KaTeXView(content: $latex, mode: .editor, fontSize: fontSize)
    }
}
