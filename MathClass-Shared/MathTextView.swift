//
//  MathTextView.swift
//  MathClass
//
//  Created by Xavier Morvan on 19.03.2026.
//

import SwiftUI

/// Native SwiftUI text view that renders mixed text and LaTeX.
/// Parses `$...$` for inline math and `$$...$$` for display math.
/// Uses italic styling for math expressions as a lightweight fallback
/// when KaTeX (WKWebView) is unavailable (e.g., in simulator sandbox).
struct MathTextView: View {
    let content: String
    var fontSize: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if line.isDisplayMath {
                    Text(line.text)
                        .font(.system(size: fontSize + 2, design: .serif))
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                } else {
                    buildInlineText(line.text)
                        .font(.system(size: fontSize))
                }
            }
        }
    }

    private struct Line {
        let text: String
        let isDisplayMath: Bool
    }

    private var lines: [Line] {
        // Split on $$ for display math blocks
        let parts = content.components(separatedBy: "$$")
        var result: [Line] = []
        for (index, part) in parts.enumerated() {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if index % 2 == 1 {
                // Inside $$ ... $$ — display math
                result.append(Line(text: trimmed, isDisplayMath: true))
            } else {
                // Regular text (may contain inline $...$)
                // Split by newlines to preserve line breaks
                for line in trimmed.components(separatedBy: "\n") {
                    let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty {
                        result.append(Line(text: t, isDisplayMath: false))
                    }
                }
            }
        }
        return result
    }

    private func buildInlineText(_ text: String) -> Text {
        // Split on single $ for inline math
        let parts = text.components(separatedBy: "$")
        var result = Text("")
        for (index, part) in parts.enumerated() {
            if part.isEmpty { continue }
            if index % 2 == 1 {
                // Inside $ ... $ — inline math
                result = result + Text(part)
                    .font(.system(size: fontSize, design: .serif))
                    .italic()
                    .foregroundColor(.blue)
            } else {
                result = result + Text(part)
            }
        }
        return result
    }
}
