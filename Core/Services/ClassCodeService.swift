//
//  ClassCodeService.swift
//  MathClass
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import CoreImage

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Generates and validates unique class codes in the format MX-XXXX.
/// Uses unambiguous characters to avoid confusion (no 0/O, 1/I/L).
class ClassCodeService {
    static let shared = ClassCodeService()

    /// Characters used for code generation — excludes 0/O, 1/I/L to prevent confusion.
    private static let codeCharacters = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    private static let codeLength = 4
    private static let prefix = "MX"

    private init() {}

    // MARK: - Code Generation

    /// Generate a unique MX-XXXX class code, verified against Firestore.
    func generateUniqueCode() async throws -> String {
        var code: String
        var attempts = 0
        let maxAttempts = 10

        repeat {
            code = generateCode()
            attempts += 1

            // Check if code already exists
            let existing = try await DataService.shared.classRepository.getClass(byCode: code)
            if existing == nil {
                return code
            }
        } while attempts < maxAttempts

        throw ClassCodeError.codeGenerationFailed
    }

    /// Generate a random MX-XXXX code (without uniqueness check).
    private func generateCode() -> String {
        let randomPart = (0..<Self.codeLength)
            .map { _ in Self.codeCharacters.randomElement()! }
        return "\(Self.prefix)-\(String(randomPart))"
    }

    // MARK: - Validation

    /// Check if a string looks like a valid class code format.
    static func isValidFormat(_ code: String) -> Bool {
        let normalized = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "^MX-[A-Z2-9]{4}$"
        return normalized.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - QR Code Generation

    /// Generate a QR code image from a class code string.
    /// Returns the QR code as platform-appropriate image data (PNG).
    static func generateQRCode(from classCode: String, size: CGFloat = 200) -> Data? {
        guard let data = classCode.data(using: .utf8) else { return nil }

        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(data, forKey: "inputMessage")
        filter?.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter?.outputImage else { return nil }

        // Scale up from the tiny default size
        let scaleX = size / ciImage.extent.size.width
        let scaleY = size / ciImage.extent.size.height
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

        #if os(iOS)
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.pngData()
        #elseif os(macOS)
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmapRep.representation(using: .png, properties: [:])
        #endif
    }

    // MARK: - Errors

    enum ClassCodeError: LocalizedError {
        case codeGenerationFailed

        var errorDescription: String? {
            switch self {
            case .codeGenerationFailed:
                return "Impossible de générer un code de classe unique. Veuillez réessayer."
            }
        }
    }
}
