//
//  NetworkMonitor.swift
//  MathClass
//
//  Tiny wrapper over Network.framework's NWPathMonitor that publishes
//  online/offline status. Used by VerificationView to surface a
//  "Waiting for connection" pill when the iPad is offline mid-submission.
//

import Foundation
import Network
import Combine

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "MathClass.NetworkMonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isOnline = online
            }
        }
        monitor.start(queue: queue)
    }
}
