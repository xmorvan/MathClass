//
//  Extensions.swift
//  MathClass
//
//  Created by Xavier Morvan on 28.03.2025.
//

import SwiftUI
import Foundation

// MARK: - Extensions View

extension View {
    /// Applique une condition sur une vue
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Crée un groupe conditionnel de modificateurs
    @ViewBuilder
    func conditionalModifier<TrueContent: View, FalseContent: View>(
        _ condition: Bool,
        if ifTransform: (Self) -> TrueContent,
        else elseTransform: (Self) -> FalseContent
    ) -> some View {
        if condition {
            ifTransform(self)
        } else {
            elseTransform(self)
        }
    }

    /// Ajoute un masque d'ombre avec overlay conditionnel
    func shadowOverlay(condition: Bool) -> some View {
        self.overlay(
            Group {
                if condition {
                    Color.black.opacity(0.4)
                        .edgesIgnoringSafeArea(.all)
                }
            }
        )
    }

    /// Ajoute une bordure conditionnelle
    func conditionalBorder(_ condition: Bool, color: Color = .blue, width: CGFloat = 2) -> some View {
        if condition {
            return AnyView(self.overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(color, lineWidth: width)
            ))
        } else {
            return AnyView(self)
        }
    }
}

// MARK: - Extensions String

extension String {
    /// Vérifie si la chaîne est une adresse email valide
    var isValidEmail: Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: self)
    }

    /// Retourne une version tronquée de la chaîne si elle est trop longue
    func truncated(length: Int, trailing: String = "...") -> String {
        return self.count > length
            ? self.prefix(length) + trailing
            : self
    }

    /// Extrait le titre d'un bloc LaTeX
    func extractLatexTitle() -> String {
        let pattern = #"\\(title|section|chapter|subsection)\{([^}]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return self.truncated(length: 30)
        }

        let nsrange = NSRange(self.startIndex..<self.endIndex, in: self)
        if let match = regex.firstMatch(in: self, options: [], range: nsrange),
           let titleRange = Range(match.range(at: 2), in: self) {
            return String(self[titleRange]).truncated(length: 30)
        }

        if let firstLine = self.split(separator: "\n").first {
            return String(firstLine).truncated(length: 30)
        }

        return self.truncated(length: 30)
    }
}

// MARK: - Extensions NSImage (macOS only)

#if os(macOS)
import AppKit

extension NSImage {
    /// Redimensionne une image
    func resized(to newSize: NSSize) -> NSImage? {
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(newSize.width),
            pixelsHigh: Int(newSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        bitmapRep.size = newSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)

        self.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: self.size),
            operation: .copy,
            fraction: 1.0
        )

        NSGraphicsContext.restoreGraphicsState()

        let resizedImage = NSImage(size: newSize)
        resizedImage.addRepresentation(bitmapRep)

        return resizedImage
    }

    /// Compresse une image avec un facteur donné
    func compressed(quality: Double = 0.7) -> Data? {
        guard let tiffData = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        )
    }
}
#endif

// MARK: - Extensions Array

extension Array {
    /// Splits the array into chunks of at most `size` elements.
    /// Used to fit Firestore `whereField(... in: ...)` queries under the
    /// 10-element cap.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Extensions Date

extension Date {
    /// Calcule l'intervalle de temps écoulé depuis cette date
    func timeElapsed() -> String {
        let components = Calendar.current.dateComponents([.minute, .hour, .day], from: self, to: Date())

        if let day = components.day, day > 0 {
            return day == 1 ? "Hier" : "Il y a \(day) jours"
        }

        if let hour = components.hour, hour > 0 {
            return "Il y a \(hour) h"
        }

        if let minute = components.minute, minute > 0 {
            return "Il y a \(minute) min"
        }

        return "À l'instant"
    }
}

