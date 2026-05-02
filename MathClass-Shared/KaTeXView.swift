//
//  KaTeXView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import SwiftUI
import WebKit

/// Cross-platform KaTeX rendering view.
/// Wraps a WKWebView that loads KaTeX from CDN and renders LaTeX content.
///
/// Usage:
///   KaTeXView(content: "Résoudre $x^2 + 3x = 0$", mode: .preview)
///   KaTeXView(content: $latex, mode: .editor)
///
/// Modes:
/// - `.preview` — read-only rendering of LaTeX/text content
/// - `.editor`  — dual-pane: LaTeX textarea + live preview, reports changes
/// - `.expression(displayMode:)` — renders a single LaTeX expression
struct KaTeXView: View {
    /// The content to render (read-only) or initial value (editor mode).
    /// For `.editor` mode, use the binding initializer instead.
    var content: String

    /// Binding variant — used in `.editor` mode to sync changes back.
    var contentBinding: Binding<String>?

    /// Rendering mode.
    var mode: Mode = .preview

    /// Font size in points.
    var fontSize: CGFloat = 18

    /// Minimum height of the view.
    var minHeight: CGFloat = 60

    enum Mode: Equatable {
        case preview
        case editor
        case expression(displayMode: Bool)
    }

    /// Read-only initializer.
    init(content: String, mode: Mode = .preview, fontSize: CGFloat = 18, minHeight: CGFloat = 60) {
        self.content = content
        self.contentBinding = nil
        self.mode = mode
        self.fontSize = fontSize
        self.minHeight = minHeight
    }

    /// Editor initializer with binding.
    init(content: Binding<String>, mode: Mode = .editor, fontSize: CGFloat = 16, minHeight: CGFloat = 200) {
        self.content = content.wrappedValue
        self.contentBinding = content
        self.mode = mode
        self.fontSize = fontSize
        self.minHeight = minHeight
    }

    var body: some View {
        KaTeXWebView(
            content: content,
            contentBinding: contentBinding,
            mode: mode,
            fontSize: fontSize
        )
        .frame(minHeight: minHeight)
    }
}

// MARK: - Platform-specific WebView wrapper

#if os(macOS)
private struct KaTeXWebView: NSViewRepresentable {
    let content: String
    var contentBinding: Binding<String>?
    let mode: KaTeXView.Mode
    let fontSize: CGFloat

    func makeCoordinator() -> KaTeXCoordinator {
        KaTeXCoordinator(contentBinding: contentBinding)
    }

    func makeNSView(context: Context) -> WKWebView {
        return createWebView(coordinator: context.coordinator)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.updateContent(content, in: webView, mode: mode)
    }
}
#else
private struct KaTeXWebView: UIViewRepresentable {
    let content: String
    var contentBinding: Binding<String>?
    let mode: KaTeXView.Mode
    let fontSize: CGFloat

    func makeCoordinator() -> KaTeXCoordinator {
        KaTeXCoordinator(contentBinding: contentBinding)
    }

    func makeUIView(context: Context) -> WKWebView {
        return createWebView(coordinator: context.coordinator)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.updateContent(content, in: webView, mode: mode)
    }
}
#endif

// MARK: - Shared creation

private extension KaTeXWebView {
    func createWebView(coordinator: KaTeXCoordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        // Register message handlers
        config.userContentController.add(coordinator, name: "latexHandler")
        config.userContentController.add(coordinator, name: "editorLoaded")
        config.userContentController.add(coordinator, name: "renderComplete")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        coordinator.webView = webView
        // Hand the coordinator the same fontSize the WebView was built with
        // so subsequent .expression updates can re-render at the right size
        // instead of falling back to the renderer's default of 22pt.
        coordinator.fontSize = fontSize

        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        #endif

        // Load the appropriate HTML
        let renderer = KaTeXRenderer.shared
        let html: String
        switch mode {
        case .preview:
            html = renderer.generatePreviewHTML(content: content, fontSize: fontSize)
        case .editor:
            html = renderer.generateEditorHTML(fontSize: fontSize)
        case .expression(let displayMode):
            html = renderer.generateSingleExpressionHTML(latex: content, fontSize: fontSize, displayMode: displayMode)
        }

        webView.loadHTMLString(html, baseURL: KaTeXRenderer.shared.katexBaseURL)
        return webView
    }
}

// MARK: - Coordinator

private class KaTeXCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var contentBinding: Binding<String>?
    weak var webView: WKWebView?
    var isLoaded: Bool = false
    var lastContent: String = ""
    /// Set by createWebView so .expression re-renders honour the caller's font size
    /// instead of silently falling back to KaTeXRenderer's default.
    var fontSize: CGFloat = 22

    init(contentBinding: Binding<String>?) {
        self.contentBinding = contentBinding
    }

    // MARK: - Script Message Handler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case "latexHandler":
            if let newValue = message.body as? String {
                DispatchQueue.main.async { [weak self] in
                    self?.contentBinding?.wrappedValue = newValue
                    self?.lastContent = newValue
                }
            }
        case "editorLoaded":
            isLoaded = true
            // Send initial content to editor
            if let binding = contentBinding {
                sendContentToEditor(binding.wrappedValue)
            }
        case "renderComplete":
            break
        default:
            break
        }
    }

    // MARK: - Navigation Delegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // For editor mode, content is sent on editorLoaded message
    }

    // MARK: - Content Updates

    func updateContent(_ content: String, in webView: WKWebView, mode: KaTeXView.Mode) {
        guard isLoaded, content != lastContent else { return }
        lastContent = content

        switch mode {
        case .preview:
            // Update preview via JS
            let encoded = encodeForJS(content)
            webView.evaluateJavaScript("window.updateContent(\(encoded));") { _, _ in }

        case .editor:
            sendContentToEditor(content)

        case .expression(let displayMode):
            // For single expressions, reload the whole HTML. The previous
            // version dropped both `fontSize` (silently jumping to the 22pt
            // default) and the case's associated `displayMode` (always
            // forcing display mode true) — fixed here.
            let html = KaTeXRenderer.shared.generateSingleExpressionHTML(
                latex: content,
                fontSize: fontSize,
                displayMode: displayMode
            )
            webView.loadHTMLString(html, baseURL: KaTeXRenderer.shared.katexBaseURL)
        }
    }

    private func sendContentToEditor(_ content: String) {
        guard let webView = webView, isLoaded else { return }
        let encoded = encodeForJS(content)
        webView.evaluateJavaScript("window.updateLatexValue(\(encoded));") { _, _ in }
    }

    private func encodeForJS(_ string: String) -> String {
        guard let data = try? JSONEncoder().encode(string),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return jsonString
    }
}
