//
//  PDFExporter.swift
//  MathClass
//
//  Cross-platform PDF export for statistics reports. Renders a SwiftUI
//  view via `ImageRenderer` (iOS 16+ / macOS 13+), then slices the
//  rendered raster into one or more pages of `pageSize` and emits a PDF.
//
//  Multi-page support (ISSUE-014 §1.15): when the rendered view is
//  taller than a single page, the exporter slices the rasterized image
//  into N pages, each drawing a translated strip. The single-page
//  path is the degenerate N=1 case — callers don't need to change.
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

    /// Export a SwiftUI view to a (possibly multi-page) PDF on disk and
    /// return the URL. The file is written to the user's temporary
    /// directory; the caller shares or moves it.
    ///
    /// The renderer rasterizes the view at its natural height. If that
    /// height exceeds `pageSize.height`, the raster is sliced into
    /// page-sized strips and each is drawn on its own page. The width is
    /// always clamped to `pageSize.width` (excess is cropped — callers
    /// should size their root view to that width).
    ///
    /// Default page size is US-Letter portrait at 72 dpi (612 × 792 pt) —
    /// matches the frame sizes the existing iOS callers already pass.
    static func exportToPDF<Content: View>(
        view: Content,
        fileName: String,
        pageSize: CGSize = CGSize(width: 612, height: 792)
    ) throws -> URL {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0  // retina
        // ImageRenderer respects the view's intrinsic frame; the report
        // views already apply a fixed width via `.frame(width:)`.

#if os(iOS)
        guard let uiImage = renderer.uiImage else {
            throw ExportError.rendererFailed
        }
        let totalSize = uiImage.size
        let url = temporaryURL(for: fileName)
        let pageRect = CGRect(origin: .zero, size: pageSize)
        let pageCount = numberOfPages(for: totalSize.height, pageHeight: pageSize.height)
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: pageRect)
        do {
            try pdfRenderer.writePDF(to: url) { context in
                for pageIndex in 0..<pageCount {
                    context.beginPage()
                    // Draw the full image translated up by pageIndex pages.
                    // UIGraphicsPDFRenderer clips to the page bounds, so
                    // only the relevant strip ends up on the page.
                    let drawRect = CGRect(
                        x: 0,
                        y: -CGFloat(pageIndex) * pageSize.height,
                        width: pageSize.width,
                        height: totalSize.height
                    )
                    uiImage.draw(in: drawRect)
                }
            }
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }
        return url
#elseif os(macOS)
        guard let nsImage = renderer.nsImage else {
            throw ExportError.rendererFailed
        }
        let totalSize = nsImage.size
        let url = temporaryURL(for: fileName)
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw ExportError.writeFailed("CGDataConsumer init failed")
        }
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw ExportError.writeFailed("CGContext init failed")
        }
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ExportError.writeFailed("NSImage → CGImage failed")
        }
        let pageCount = numberOfPages(for: totalSize.height, pageHeight: pageSize.height)
        for pageIndex in 0..<pageCount {
            context.beginPDFPage(nil)
            // CoreGraphics' origin is bottom-left: place the image so the
            // strip for this page (counted from the top) fills the media
            // box, which clips the rest. Short content sits at the top.
            let drawRect = CGRect(
                x: 0,
                y: pageSize.height - totalSize.height + CGFloat(pageIndex) * pageSize.height,
                width: pageSize.width,
                height: totalSize.height
            )
            context.draw(cgImage, in: drawRect)
            context.endPDFPage()
        }
        context.closePDF()
        return url
#else
        throw ExportError.rendererFailed
#endif
    }

    private static func numberOfPages(for totalHeight: CGFloat, pageHeight: CGFloat) -> Int {
        guard pageHeight > 0 else { return 1 }
        // ImageRenderer.scale=2 doubles the raster but the draw rect uses
        // points, so totalHeight here is already in points.
        let pages = Int((totalHeight / pageHeight).rounded(.up))
        return max(1, pages)
    }

    private static func temporaryURL(for fileName: String) -> URL {
        let safe = fileName.replacingOccurrences(of: "/", with: "-")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(safe)
            .appendingPathExtension("pdf")
    }
}
