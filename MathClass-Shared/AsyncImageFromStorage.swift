//
//  AsyncImageFromStorage.swift
//  MathClass
//
//  Created by Xavier Morvan on 06.02.2025.
//

import SwiftUI
import Foundation
import FirebaseStorage

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Cross-platform view that asynchronously loads an image from Firebase Cloud Storage.
struct AsyncImageFromStorage: View {
    let path: String

    #if os(macOS)
    @State private var platformImage: NSImage?
    #else
    @State private var platformImage: UIImage?
    #endif

    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let img = platformImage {
                #if os(macOS)
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                #else
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                #endif
            } else if isLoading {
                ProgressView("Chargement de l'image...")
            } else if let errorMessage = errorMessage {
                // ISSUE-016 — when the PNG can't be loaded (deleted file,
                // permission denied, transient network error), surface a
                // retry affordance instead of a dead red text node.
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Image indisponible")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Réessayer") {
                        self.errorMessage = nil
                        loadImage()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 8)
            } else {
                Color.clear.onAppear(perform: loadImage)
            }
        }
    }

    private func loadImage() {
        isLoading = true
        let ref = Storage.storage().reference().child(path)
        ref.getData(maxSize: 10 * 1024 * 1024) { data, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let data = data else {
                    self.errorMessage = "Données d'image vides."
                    return
                }
                #if os(macOS)
                if let image = NSImage(data: data) {
                    self.platformImage = image
                } else {
                    self.errorMessage = "Impossible de décoder l'image."
                }
                #else
                if let image = UIImage(data: data) {
                    self.platformImage = image
                } else {
                    self.errorMessage = "Impossible de décoder l'image."
                }
                #endif
            }
        }
    }
}
