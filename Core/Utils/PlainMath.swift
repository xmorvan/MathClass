//
//  PlainMath.swift
//  MathClass
//
//  The keyboard notation students type ("1/2", "x^2", "√(2)", "3 × 4",
//  "≤", "π") and its conversion to and from the LaTeX the correction reads.
//  Students never see LaTeX: a recognised line opens in this notation, and
//  what they type is converted back.
//

import Foundation

enum PlainMath {

    /// Symbols offered above the keyboard, with what each one inserts.
    static let keys: [(label: String, insert: String)] = [
        ("a/b", "/"), ("x²", "^"), ("√", "√("), ("×", "×"), ("÷", "÷"),
        ("(", "("), (")", ")"), ("π", "π"), ("≤", "≤"), ("≥", "≥"), ("≠", "≠")
    ]

    // MARK: - LaTeX → keyboard notation

    /// "\\frac{x+1}{2}" → "(x+1)/2", "\\sqrt{2}" → "√2", "x^{2}" → "x^2".
    /// Commands without a keyboard form (\\int, \\binom…) are kept as they are.
    static func fromLatex(_ latex: String) -> String {
        var text = latex
        for (command, symbol) in latexSymbols {
            text = text.replacingOccurrences(of: command, with: symbol)
        }
        text = replaceCommand("\\text", in: text) { args in " \(args[0].trimmingCharacters(in: .whitespaces)) " }
        text = replaceCommand("\\mathrm", in: text) { args in args[0] }
        for name in ["\\frac", "\\dfrac", "\\tfrac"] {
            text = replaceCommand(name, arguments: 2, in: text) { args in
                "\(wrapped(fromLatex(args[0])))/\(wrapped(fromLatex(args[1])))"
            }
        }
        text = replaceCommand("\\sqrt", in: text) { args in "√\(wrapped(fromLatex(args[0])))" }
        text = replaceGroup(after: "^", in: text) { "^\(wrapped(fromLatex($0)))" }
        text = replaceGroup(after: "_", in: text) { "_\(wrapped(fromLatex($0)))" }
        for function in functions {
            text = text.replacingOccurrences(of: "\\\(function)", with: function)
        }
        return text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Keyboard notation → LaTeX

    /// "(x+1)/2" → "\\frac{x+1}{2}", "√(2)" → "\\sqrt{2}", "x^12" → "x^{12}",
    /// "3 × 4" → "3 \\times 4", "x = 2 ou x = 3" → "x = 2 \\text{ ou } x = 3".
    static func toLatex(_ plain: String) -> String {
        var text = plain
        for (symbol, command) in plainSymbols {
            text = text.replacingOccurrences(of: symbol, with: " \(command) ")
        }
        // π and ∞ are numbers: "5π/6" is the fraction of 5π.
        for (symbol, command) in [("π", "\\pi"), ("∞", "\\infty")] {
            text = text.replacingOccurrences(of: symbol, with: "\(command) ")
        }
        text = convertRoots(text)
        text = convertExponents(text, marker: "^")
        text = convertExponents(text, marker: "_")
        text = convertFractions(text)
        text = convertWords(text)
        return text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Tables

    private static let functions = ["arcsin", "arccos", "arctan", "sin", "cos", "tan", "ln", "log", "exp", "lim"]

    private static let latexSymbols: [(String, String)] = [
        ("\\left", ""), ("\\right", ""),
        ("\\leqslant", "≤"), ("\\geqslant", "≥"), ("\\leq", "≤"), ("\\geq", "≥"),
        ("\\le ", "≤ "), ("\\ge ", "≥ "), ("\\neq", "≠"), ("\\approx", "≈"),
        ("\\times", "×"), ("\\cdot", "×"), ("\\div", "÷"), ("\\pi", "π"), ("\\infty", "∞"),
        ("\\,", " "), ("\\;", " "), ("\\!", ""), ("\\ ", " ")
    ]

    private static let plainSymbols: [(String, String)] = [
        ("≤", "\\leq"), ("≥", "\\geq"), ("≠", "\\neq"), ("≈", "\\approx"),
        ("×", "\\times"), ("*", "\\times"), ("·", "\\times"), ("÷", "\\div")
    ]

    // MARK: - LaTeX parsing helpers

    /// "(x+1)" for a compound argument, the argument itself when it is a
    /// single number or letter.
    private static func wrapped(_ argument: String) -> String {
        let trimmed = argument.trimmingCharacters(in: .whitespaces)
        let atomic = trimmed.range(of: #"^(-?[0-9]+([.,][0-9]+)?|[A-Za-zπ∞]|[A-Za-z]+_[0-9A-Za-z])$"#, options: .regularExpression) != nil
        return atomic ? trimmed : "(\(trimmed))"
    }

    /// The content of the brace group opening at `index`, and the index
    /// just past its closing brace.
    private static func braceGroup(in chars: [Character], at index: Int) -> (String, Int)? {
        guard index < chars.count, chars[index] == "{" else { return nil }
        var depth = 0
        for position in index..<chars.count {
            if chars[position] == "{" { depth += 1 }
            if chars[position] == "}" {
                depth -= 1
                if depth == 0 { return (String(chars[(index + 1)..<position]), position + 1) }
            }
        }
        return nil
    }

    /// Replaces `\\command{a}{b}…` with `transform([a, b…])`.
    private static func replaceCommand(_ command: String, arguments: Int = 1, in text: String, _ transform: ([String]) -> String) -> String {
        let chars = Array(text)
        let name = Array(command)
        var result = ""
        var index = 0
        while index < chars.count {
            let end = index + name.count
            let nextIsLetter = end < chars.count && chars[end].isLetter
            if end <= chars.count, Array(chars[index..<end]) == name, !nextIsLetter {
                var cursor = end
                while cursor < chars.count, chars[cursor] == " " { cursor += 1 }
                var args: [String] = []
                while args.count < arguments, let (argument, next) = braceGroup(in: chars, at: cursor) {
                    args.append(argument)
                    cursor = next
                }
                if args.count == arguments {
                    result += transform(args)
                    index = cursor
                    continue
                }
            }
            result.append(chars[index])
            index += 1
        }
        return result
    }

    /// Replaces `^{…}` (or `_{…}`) with `transform(content)`.
    private static func replaceGroup(after marker: Character, in text: String, _ transform: (String) -> String) -> String {
        let chars = Array(text)
        var result = ""
        var index = 0
        while index < chars.count {
            if chars[index] == marker, let (content, next) = braceGroup(in: chars, at: index + 1) {
                result += transform(content)
                index = next
                continue
            }
            result.append(chars[index])
            index += 1
        }
        return result
    }

    // MARK: - Keyboard parsing helpers

    /// "√(x+1)" → "\\sqrt{x+1}", "√12" → "\\sqrt{12}".
    private static func convertRoots(_ text: String) -> String {
        let chars = Array(text)
        var result = ""
        var index = 0
        while index < chars.count {
            guard chars[index] == "√" else {
                result.append(chars[index])
                index += 1
                continue
            }
            var cursor = index + 1
            while cursor < chars.count, chars[cursor] == " " { cursor += 1 }
            if let (content, next) = parenGroup(in: chars, at: cursor) {
                result += "\\sqrt{\(convertRoots(content))}"
                index = next
            } else {
                let run = atomRun(in: chars, from: cursor)
                result += "\\sqrt{\(String(chars[cursor..<run]))}"
                index = run
            }
        }
        return result
    }

    /// "x^12" → "x^{12}", "x^(n+1)" → "x^{n+1}", "e^-x" → "e^{-x}".
    private static func convertExponents(_ text: String, marker: Character) -> String {
        let chars = Array(text)
        var result = ""
        var index = 0
        while index < chars.count {
            guard chars[index] == marker, index + 1 < chars.count, chars[index + 1] != "{" else {
                result.append(chars[index])
                index += 1
                continue
            }
            let start = index + 1
            if let (content, next) = parenGroup(in: chars, at: start) {
                result += "\(marker){\(content)}"
                index = next
            } else {
                var cursor = start
                if cursor < chars.count, chars[cursor] == "-" { cursor += 1 }
                let end = atomRun(in: chars, from: cursor)
                result += "\(marker){\(String(chars[start..<end]))}"
                index = end
            }
        }
        return result
    }

    /// "a/b" → "\\frac{a}{b}", each side being a bracketed group, a number,
    /// a letter run, or a command with its braces (\\sqrt{2}, x^{2}).
    private static func convertFractions(_ text: String) -> String {
        var chars = Array(text)
        while let slash = chars.firstIndex(of: "/") {
            // Left operand.
            var left = slash
            while left > 0, chars[left - 1] == " " { left -= 1 }
            let leftEnd = left
            if left > 0, chars[left - 1] == ")" {
                left = matchingOpen(in: chars, closeAt: left - 1) ?? left
            } else {
                left = operandStart(in: chars, before: leftEnd)
            }
            // Right operand.
            var right = slash + 1
            while right < chars.count, chars[right] == " " { right += 1 }
            let rightStart = right
            if let (_, next) = parenGroup(in: chars, at: right) {
                right = next
            } else {
                right = operandEnd(in: chars, from: right)
            }
            guard left < leftEnd, rightStart < right else {
                chars[slash] = "∕"  // not a fraction: keep a slash, stop matching it
                continue
            }
            let numerator = stripParens(String(chars[left..<leftEnd]))
            let denominator = stripParens(String(chars[rightStart..<right]))
            let replacement = Array("\\frac{\(numerator)}{\(denominator)}")
            chars.replaceSubrange(left..<right, with: replacement)
        }
        return String(chars).replacingOccurrences(of: "∕", with: "/")
    }

    /// Words other than variables become text ("ou", "cm", "billes");
    /// known functions become commands (sin → \\sin).
    private static func convertWords(_ text: String) -> String {
        let pattern = #"(?<![\\A-Za-zÀ-ÿ])[A-Za-zÀ-ÿ]{2,}(?![A-Za-zÀ-ÿ])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed()
        for match in matches {
            guard let range = Range(match.range, in: result) else { continue }
            let word = String(result[range])
            let replacement: String
            if functions.contains(word) {
                replacement = "\\\(word)"
            } else if word.allSatisfy({ "abcdnxyzt".contains($0) }) {
                continue  // a product of variables ("xy")
            } else if isInsideCommandArgument(result, at: range.lowerBound) {
                continue
            } else {
                replacement = "\\text{ \(word) }"
            }
            result.replaceSubrange(range, with: replacement)
        }
        return result.replacingOccurrences(of: #"\\text\{ ([^}]*) \} \\text\{ ([^}]*) \}"#, with: #"\\text{ $1 $2 }"#, options: .regularExpression)
    }

    /// True inside the braces of a command already converted (\\text{…}).
    private static func isInsideCommandArgument(_ text: String, at index: String.Index) -> Bool {
        let before = text[..<index]
        guard let open = before.range(of: "\\text{", options: .backwards) else { return false }
        return !before[open.upperBound...].contains("}")
    }

    private static func parenGroup(in chars: [Character], at index: Int) -> (String, Int)? {
        guard index < chars.count, chars[index] == "(" else { return nil }
        var depth = 0
        for position in index..<chars.count {
            if chars[position] == "(" { depth += 1 }
            if chars[position] == ")" {
                depth -= 1
                if depth == 0 { return (String(chars[(index + 1)..<position]), position + 1) }
            }
        }
        return nil
    }

    private static func matchingOpen(in chars: [Character], closeAt index: Int) -> Int? {
        var depth = 0
        var position = index
        while position >= 0 {
            if chars[position] == ")" { depth += 1 }
            if chars[position] == "(" {
                depth -= 1
                if depth == 0 { return position }
            }
            position -= 1
        }
        return nil
    }

    /// End of a number or letter run ("12", "3,5", "x", "ab").
    private static func atomRun(in chars: [Character], from index: Int) -> Int {
        var cursor = index
        while cursor < chars.count, chars[cursor].isNumber || chars[cursor].isLetter || ((chars[cursor] == "," || chars[cursor] == ".") && cursor + 1 < chars.count && chars[cursor + 1].isNumber) {
            cursor += 1
        }
        return cursor
    }

    /// Start of the operand ending at `end`: a number/letter run, possibly
    /// with an exponent or a command and its braces (x^{2}, \\sqrt{3}).
    private static func operandStart(in chars: [Character], before end: Int) -> Int {
        var cursor = end
        while cursor > 0 {
            let char = chars[cursor - 1]
            if char == "}" {
                var depth = 0
                var position = cursor - 1
                while position >= 0 {
                    if chars[position] == "}" { depth += 1 }
                    if chars[position] == "{" { depth -= 1; if depth == 0 { break } }
                    position -= 1
                }
                cursor = max(position, 0)
                continue
            }
            if char.isNumber || char.isLetter || char == "\\" || char == "^" || char == "_" || ((char == "," || char == ".") && cursor >= 2 && chars[cursor - 2].isNumber) {
                cursor -= 1
                continue
            }
            break
        }
        return cursor
    }

    /// End of the operand starting at `start` (same shapes as operandStart).
    private static func operandEnd(in chars: [Character], from start: Int) -> Int {
        var cursor = start
        if cursor < chars.count, chars[cursor] == "-" { cursor += 1 }
        while cursor < chars.count {
            let char = chars[cursor]
            if char == "{" {
                guard let (_, next) = braceGroup(in: chars, at: cursor) else { break }
                cursor = next
                continue
            }
            if char.isNumber || char.isLetter || char == "\\" || char == "^" || char == "_" || ((char == "," || char == ".") && cursor + 1 < chars.count && chars[cursor + 1].isNumber) {
                cursor += 1
                continue
            }
            break
        }
        return cursor
    }

    private static func stripParens(_ operand: String) -> String {
        let trimmed = operand.trimmingCharacters(in: .whitespaces)
        let chars = Array(trimmed)
        if let (content, next) = parenGroup(in: chars, at: 0), next == chars.count {
            return content
        }
        return trimmed
    }
}
