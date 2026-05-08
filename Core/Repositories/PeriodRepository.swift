//
//  PeriodRepository.swift
//  MathClass
//

import Foundation
import FirebaseFirestore
import Combine

@MainActor
final class PeriodRepository: ObservableObject {
    @Published private(set) var periods: [Period] = []
    @Published private(set) var isLoading: Bool = false
    @Published var error: String?

    private let firebase = FirebaseService.shared
    private var listener: ListenerRegistration?

    deinit {
        listener?.remove()
    }

    private let collectionPath = "periods"

    /// Listen for periods of a single class, ordered by startTime ascending.
    func startListening(classID: String) {
        listener?.remove()
        listener = firebase.addQueryListener(
            from: collectionPath,
            whereField: "classID",
            isEqualTo: classID
        ) { [weak self] (periods: [Period]) in
            self?.periods = periods.sorted { $0.startTime < $1.startTime }
        }
    }

    /// Listen across multiple classes (used by the macOS teacher dashboard
    /// when the teacher has more than one class). Falls back to listening
    /// for everything and filtering client-side because Firestore's `in`
    /// query is capped at 30 values; for typical 1–5 classes that's fine.
    func startListeningAcrossClasses(classIDs: [String]) {
        listener?.remove()
        guard !classIDs.isEmpty else {
            self.periods = []
            return
        }
        let allowed = Set(classIDs)
        listener = firebase.addCollectionListener(
            collection: collectionPath
        ) { [weak self] (periods: [Period]) in
            self?.periods = periods
                .filter { allowed.contains($0.classID) }
                .sorted { $0.startTime < $1.startTime }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    func createPeriod(_ period: Period) async throws -> String {
        let ref = try await firebase.createDocument(period, in: collectionPath)
        return ref.documentID
    }

    func updatePeriod(_ period: Period) async throws {
        guard let id = period.id else { return }
        try await firebase.updateDocument(period, in: collectionPath, documentID: id)
    }

    func deletePeriod(id: String) async throws {
        try await firebase.deleteDocument(from: collectionPath, documentID: id)
    }

    func getPeriod(id: String) async throws -> Period {
        try await firebase.getDocument(id, from: collectionPath)
    }

    /// Mark a period active and all others in the same class inactive.
    func setActive(_ period: Period) async throws {
        guard let activeID = period.id else { return }
        // Optimistic: deactivate every other period for the same class.
        let others = periods.filter { $0.classID == period.classID && $0.id != activeID && $0.isActive }
        for other in others {
            var deactivated = other
            deactivated.isActive = false
            try await updatePeriod(deactivated)
        }
        var updated = period
        updated.isActive = true
        try await updatePeriod(updated)
    }
}
