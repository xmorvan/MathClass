//
//  QRScannerView.swift
//  MathClassApp
//
//  AVFoundation-based QR scanner used in the iPad student onboarding flow.
//  Returns the scanned class code (e.g. "MX-AB12") via the `onScan` closure
//  and dismisses itself. Failures (camera permission denied, not on a real
//  device, etc.) are surfaced via `onError` so the parent view can fall
//  back to manual code entry.
//

import SwiftUI

#if os(iOS)
import AVFoundation
import UIKit

/// SwiftUI wrapper around `AVCaptureSession` for QR scanning. iPad-only.
struct QRScannerView: UIViewControllerRepresentable {

    /// Called once when a QR code matching the class-code format is read.
    /// Subsequent scans are ignored until the controller is dismissed.
    var onScan: (String) -> Void
    /// Called when the camera session fails to start, typically because
    /// permission was denied or the device has no camera.
    var onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onError: onError)
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.coordinator = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onScan: (String) -> Void
        let onError: (String) -> Void
        private var didScan: Bool = false

        init(onScan: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onScan = onScan
            self.onError = onError
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !didScan else { return }
            guard
                let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                let raw = object.stringValue
            else { return }
            // Accept a wide range of payloads — the parent view validates
            // the MX-XXXX format and shows an error if needed.
            didScan = true
            DispatchQueue.main.async {
                self.onScan(raw)
            }
        }
    }

    final class ScannerViewController: UIViewController {
        weak var coordinator: Coordinator?
        private var captureSession: AVCaptureSession?
        private var previewLayer: AVCaptureVideoPreviewLayer?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            startSession()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            if let session = captureSession, !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async {
                    session.startRunning()
                }
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            captureSession?.stopRunning()
        }

        private func startSession() {
            let session = AVCaptureSession()
            captureSession = session

            guard let device = AVCaptureDevice.default(for: .video) else {
                coordinator?.onError("Aucune caméra disponible.")
                return
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                } else {
                    coordinator?.onError("Impossible d'utiliser la caméra.")
                    return
                }

                let output = AVCaptureMetadataOutput()
                if session.canAddOutput(output) {
                    session.addOutput(output)
                    output.setMetadataObjectsDelegate(coordinator, queue: .main)
                    output.metadataObjectTypes = [.qr]
                } else {
                    coordinator?.onError("Impossible de démarrer la lecture QR.")
                    return
                }

                let preview = AVCaptureVideoPreviewLayer(session: session)
                preview.frame = view.bounds
                preview.videoGravity = .resizeAspectFill
                view.layer.addSublayer(preview)
                previewLayer = preview

                DispatchQueue.global(qos: .userInitiated).async {
                    session.startRunning()
                }
            } catch {
                coordinator?.onError(error.localizedDescription)
            }
        }
    }
}
#endif
