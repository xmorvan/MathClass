//
//  ShareSheet.swift
//  MathClassApp
//
//  Tiny SwiftUI wrapper around UIActivityViewController. Used by the
//  iPad statistics export to surface the generated PDF for AirDrop /
//  Save to Files / Mail.
//

import SwiftUI

#if os(iOS)
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    /// Present the system share sheet from UIKit. On iPad a
    /// UIActivityViewController wrapped in a SwiftUI `.sheet` comes up
    /// empty; it has to be a popover anchored in the window.
    @MainActor
    static func present(items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first,
              var top = window.rootViewController
        else { return }
        while let presented = top.presentedViewController { top = presented }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            // Top-right corner, where the export button sits.
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.maxX - 40, y: 120, width: 1, height: 1)
            popover.permittedArrowDirections = [.up]
        }
        top.present(controller, animated: true)
    }
}
#endif
