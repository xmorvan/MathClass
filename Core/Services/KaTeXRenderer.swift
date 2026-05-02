//
//  KaTeXRenderer.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation

/// Centralized KaTeX HTML generator.
/// Replaces MathLiveManager — single CDN source (jsdelivr.net), pinned version.
/// Two rendering modes: read-only preview and editable textarea with live preview.
final class KaTeXRenderer {

    static let shared = KaTeXRenderer()

    /// Pinned KaTeX version — bundled locally to avoid CDN/sandbox issues.
    private let katexVersion = "0.16.11"

    private init() {}

    // MARK: - Local Bundle URLs (fallback to CDN)

    /// Base URL for the bundled KaTeX files, used by WKWebView to resolve relative paths.
    var katexBaseURL: URL? {
        Bundle.main.url(forResource: "katex.min", withExtension: "js")
            .map { $0.deletingLastPathComponent() }
    }

    private var katexCSS: String {
        if katexBaseURL != nil { return "katex.min.css" }
        return "https://cdn.jsdelivr.net/npm/katex@\(katexVersion)/dist/katex.min.css"
    }

    private var katexJS: String {
        if katexBaseURL != nil { return "katex.min.js" }
        return "https://cdn.jsdelivr.net/npm/katex@\(katexVersion)/dist/katex.min.js"
    }

    private var autoRenderJS: String {
        if katexBaseURL != nil { return "auto-render.min.js" }
        return "https://cdn.jsdelivr.net/npm/katex@\(katexVersion)/dist/contrib/auto-render.min.js"
    }

    // MARK: - Read-Only Preview

    /// Generates HTML that renders the given LaTeX expression(s) read-only.
    /// Supports both inline (`$...$` or `\(...\)`) and display (`$$...$$` or `\[...\]`) math
    /// mixed with plain text.
    func generatePreviewHTML(
        content: String,
        fontSize: CGFloat = 18,
        mathColor: String = "black"
    ) -> String {
        let escapedContent = escapeForJS(content)

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <link rel="stylesheet" href="\(katexCSS)"
                  crossorigin="anonymous">
            <script defer src="\(katexJS)"
                    crossorigin="anonymous"></script>
            <script defer src="\(autoRenderJS)"
                    crossorigin="anonymous"
                    onload="renderContent()"></script>
            <style>
                html, body {
                    margin: 0;
                    padding: 8px;
                    background: transparent;
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    font-size: \(fontSize)px;
                    color: \(mathColor);
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                }
                .katex-display { margin: 0.5em 0; }
                .katex { font-size: 1.1em; }
                #content { white-space: pre-wrap; }
                .render-error {
                    color: #e74c3c;
                    font-family: monospace;
                    font-size: 0.85em;
                }
            </style>
        </head>
        <body>
            <div id="content">\(escapeForHTML(content))</div>
            <script>
                function renderContent() {
                    var el = document.getElementById('content');
                    renderMathInElement(el, {
                        delimiters: [
                            {left: '$$', right: '$$', display: true},
                            {left: '$', right: '$', display: false},
                            {left: '\\\\(', right: '\\\\)', display: false},
                            {left: '\\\\[', right: '\\\\]', display: true}
                        ],
                        throwOnError: false,
                        errorColor: '#e74c3c'
                    });
                    // Notify Swift when rendering is done
                    try {
                        window.webkit.messageHandlers.renderComplete.postMessage('done');
                    } catch(e) {}
                }

                // Allow Swift to update content dynamically
                window.updateContent = function(newContent) {
                    var el = document.getElementById('content');
                    el.innerHTML = newContent.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/\\n/g,'<br>');
                    renderContent();
                };
            </script>
        </body>
        </html>
        """
    }

    // MARK: - Editable Editor with Live Preview

    /// Generates HTML for a dual-pane editor: LaTeX textarea on the left,
    /// live KaTeX preview on the right.
    /// Communicates changes back to Swift via `window.webkit.messageHandlers.latexHandler`.
    func generateEditorHTML(fontSize: CGFloat = 16) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <link rel="stylesheet" href="\(katexCSS)"
                  crossorigin="anonymous">
            <script defer src="\(katexJS)"
                    crossorigin="anonymous"></script>
            <script defer src="\(autoRenderJS)"
                    crossorigin="anonymous"
                    onload="init()"></script>
            <style>
                * { box-sizing: border-box; margin: 0; padding: 0; }
                html, body {
                    width: 100%; height: 100%;
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    font-size: \(fontSize)px;
                    background: transparent;
                    overflow: hidden;
                }
                .container {
                    display: flex;
                    flex-direction: row;
                    width: 100%;
                    height: 100%;
                }
                .editor-pane {
                    flex: 1;
                    display: flex;
                    flex-direction: column;
                    border-right: 1px solid #ddd;
                }
                .preview-pane {
                    flex: 1;
                    padding: 12px;
                    overflow-y: auto;
                }
                .editor-label, .preview-label {
                    font-size: 11px;
                    font-weight: 600;
                    color: #888;
                    text-transform: uppercase;
                    letter-spacing: 0.5px;
                    padding: 8px 12px 4px;
                }
                #latex-input {
                    flex: 1;
                    font-family: 'SF Mono', 'Menlo', monospace;
                    font-size: \(fontSize)px;
                    padding: 12px;
                    border: none;
                    outline: none;
                    resize: none;
                    background: transparent;
                }
                #preview {
                    white-space: pre-wrap;
                    word-wrap: break-word;
                }
                .katex-display { margin: 0.5em 0; }
                .katex { font-size: 1.1em; }
                .placeholder {
                    color: #aaa;
                    font-style: italic;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="editor-pane">
                    <div class="editor-label">LaTeX</div>
                    <textarea id="latex-input"
                              placeholder="Tapez du texte et du LaTeX ici...\\nUtilisez $...$ pour les maths en ligne et $$...$$ pour les équations."></textarea>
                </div>
                <div class="preview-pane">
                    <div class="preview-label">Aperçu</div>
                    <div id="preview"><span class="placeholder">L'aperçu apparaîtra ici…</span></div>
                </div>
            </div>

            <script>
                var latexInput, previewEl;
                var debounceTimer = null;

                function init() {
                    latexInput = document.getElementById('latex-input');
                    previewEl = document.getElementById('preview');

                    latexInput.addEventListener('input', function() {
                        clearTimeout(debounceTimer);
                        debounceTimer = setTimeout(function() {
                            updatePreview();
                            notifySwift();
                        }, 200);
                    });

                    // Notify Swift that the editor is ready
                    try {
                        window.webkit.messageHandlers.editorLoaded.postMessage('ready');
                    } catch(e) {}
                }

                function updatePreview() {
                    var text = latexInput.value;
                    if (!text.trim()) {
                        previewEl.innerHTML = '<span class="placeholder">L\\'aperçu apparaîtra ici…</span>';
                        return;
                    }
                    previewEl.textContent = text;
                    renderMathInElement(previewEl, {
                        delimiters: [
                            {left: '$$', right: '$$', display: true},
                            {left: '$', right: '$', display: false},
                            {left: '\\\\(', right: '\\\\)', display: false},
                            {left: '\\\\[', right: '\\\\]', display: true}
                        ],
                        throwOnError: false,
                        errorColor: '#e74c3c'
                    });
                }

                function notifySwift() {
                    try {
                        window.webkit.messageHandlers.latexHandler.postMessage(latexInput.value);
                    } catch(e) {}
                }

                // Called from Swift to set content
                window.updateLatexValue = function(text) {
                    if (document.activeElement === latexInput) return;
                    latexInput.value = text;
                    updatePreview();
                };
            </script>
        </body>
        </html>
        """
    }

    // MARK: - Single Expression Render

    /// Generates minimal HTML to render a single LaTeX expression (display mode).
    /// Used for answer previews, step displays, etc.
    func generateSingleExpressionHTML(
        latex: String,
        fontSize: CGFloat = 22,
        displayMode: Bool = true
    ) -> String {
        let escapedLatex = escapeForJS(latex)

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <link rel="stylesheet" href="\(katexCSS)" crossorigin="anonymous">
            <script src="\(katexJS)" crossorigin="anonymous"></script>
            <style>
                html, body {
                    margin: 0; padding: 8px;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    min-height: 100%;
                    background: transparent;
                }
                .katex { font-size: \(fontSize)px; }
                .error { color: #e74c3c; font-family: monospace; font-size: 14px; }
            </style>
        </head>
        <body>
            <div id="math"></div>
            <script>
                try {
                    katex.render("\(escapedLatex)", document.getElementById('math'), {
                        displayMode: \(displayMode ? "true" : "false"),
                        throwOnError: false,
                        errorColor: '#e74c3c'
                    });
                } catch(e) {
                    document.getElementById('math').innerHTML =
                        '<span class="error">' + e.message + '</span>';
                }
            </script>
        </body>
        </html>
        """
    }

    // MARK: - Validation

    /// Basic LaTeX syntax validation (balanced braces/brackets).
    func validateLaTeX(_ latex: String) -> (isValid: Bool, error: String?) {
        let openBraces = latex.filter { $0 == "{" }.count
        let closeBraces = latex.filter { $0 == "}" }.count
        let openBrackets = latex.filter { $0 == "[" }.count
        let closeBrackets = latex.filter { $0 == "]" }.count

        if openBraces != closeBraces {
            return (false, "Accolades non équilibrées dans le LaTeX")
        }
        if openBrackets != closeBrackets {
            return (false, "Crochets non équilibrés dans le LaTeX")
        }
        return (true, nil)
    }

    // MARK: - Private Helpers

    /// Escapes a string for safe embedding inside HTML content.
    /// Converts newlines to `<br>` and escapes HTML entities.
    private func escapeForHTML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    /// Escapes a string for safe embedding inside a JavaScript string literal
    /// that itself lives inside an HTML `<script>` block. Beyond the obvious
    /// quote/backslash/newline pairs we also have to:
    ///   - escape `</` so a literal `</script>` in the LaTeX cannot break out
    ///     of the surrounding script tag and inject HTML;
    ///   - escape U+2028 / U+2029, which JavaScript treats as line terminators
    ///     and which would otherwise turn into syntax errors.
    private func escapeForJS(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "</", with: "<\\/")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}
