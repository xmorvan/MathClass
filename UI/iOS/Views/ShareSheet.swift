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
}
#endif
