//
//  PDFExporter.swift
//  MathClass
//
//  Cross-platform PDF export for statistics reports. Uses SwiftUI's
//  `ImageRenderer` (iOS 16+ / macOS 13+) to rasterize a view, then
//  packages it into a single-page PDF via PDFKit on iOS and
//  CGContext.makePDF on macOS.
//
//  Single-page is intentional for MVP: the salesperson exports a per-
//  student or per-exercise summary; multi-page can be added later.
//

import SwiftUI
#if os(iOS)
import UIKit
import PDFKit
#elseif os(macOS)
import AppKit
import PDFKit
#endif

@MainActor
enum PDFExporter {

    enum ExportError: Error, LocalizedError {
        case rendererFailed
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .rendererFailed:
                return "Impossible de générer le PDF — réessayez après avoir fait défiler la vue."
            case .writeFailed(let reason):
                return "Échec d'écriture du PDF : \(reason)"
            }
        }
    }

    /// Export a SwiftUI view to a single-page PDF on disk and return the URL.
    /// The file is written to the user's temporary directory; the caller
    /// is responsible for sharing or moving it.
    static func exportToPDF<Content: View>(
        view: Content,
        fileName: String
    ) throws -> URL {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0  // retina

#if os(iOS)
        guard let uiImage = renderer.uiImage else {
            throw ExportError.rendererFailed
        }
        let pageRect = CGRect(origin: .zero, size: uiImage.size)
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let url = temporaryURL(for: fileName)
        do {
            try pdfRenderer.writePDF(to: url) { context in
                context.beginPage()
                uiImage.draw(in: pageRect)
            }
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }
        return url
#elseif os(macOS)
        guard let nsImage = renderer.nsImage else {
            throw ExportError.rendererFailed
        }
        let pageRect = CGRect(origin: .zero, size: nsImage.size)
        let url = temporaryURL(for: fileName)
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw ExportError.writeFailed("CGDataConsumer init failed")
        }
        var box = pageRect
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw ExportError.writeFailed("CGContext init failed")
        }
        context.beginPDFPage(nil)
        if let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(cgImage, in: pageRect)
        }
        context.endPDFPage()
        context.closePDF()
        return url
#else
        throw ExportError.rendererFailed
#endif
    }

    private static func temporaryURL(for fileName: String) -> URL {
        let safe = fileName.replacingOccurrences(of: "/", with: "-")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(safe)
            .appendingPathExtension("pdf")
    }
}
