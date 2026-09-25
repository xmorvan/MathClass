//
//  ClassCodeService.swift
//  MathClass
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import CoreImage
import FirebaseFunctions

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Obtains and validates unique class codes in the format MX-XXXX.
/// Codes are generated server-side (`generate_class_code`) from unambiguous
/// characters (no 0/O, 1/I/L).
class ClassCodeService {
    static let shared = ClassCodeService()

    private let functions: Functions = Functions.functions(region: "europe-west6")

    private init() {}

    // MARK: - Code Generation

    /// Get a unique MX-XXXX class code from the `generate_class_code`
    /// Cloud Function. The uniqueness check runs server-side because the
    /// security rules don't let a teacher search other teachers' classes.
    func generateUniqueCode() async throws -> String {
        let result = try await functions.httpsCallable("generate_class_code").call()
        guard let dict = result.data as? [String: Any],
              let code = dict["classCode"] as? String,
              Self.isValidFormat(code) else {
            throw ClassCodeError.codeGenerationFailed
        }
        return code
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
