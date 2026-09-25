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
    /// Per-chunk listeners for `startListeningAcrossClasses` (Firestore caps
    /// `in` at 30 values), merged by period ID.
    private var chunkListeners: [ListenerRegistration] = []
    private var chunkResults: [Int: [Period]] = [:]

    deinit {
        listener?.remove()
        chunkListeners.forEach { $0.remove() }
    }

    private let collectionPath = "periods"

    /// Listen for periods of a single class, ordered by startTime ascending.
    func startListening(classID: String) {
        stopListening()
        listener = firebase.addQueryListener(
            from: collectionPath,
            whereField: "classID",
            isEqualTo: classID
        ) { [weak self] (periods: [Period]) in
            self?.periods = periods.sorted { $0.startTime < $1.startTime }
        }
    }

    /// Listen across multiple classes (used by the macOS teacher dashboard
    /// when the teacher has more than one class). One `classID in [...]`
    /// listener per 30 classes — the security rules refuse a listener on the
    /// whole collection, since it would include other teachers' periods.
    func startListeningAcrossClasses(classIDs: [String]) {
        stopListening()
        guard !classIDs.isEmpty else {
            self.periods = []
            return
        }
        for (index, chunk) in classIDs.chunked(into: 30).enumerated() {
            let query = firebase.db.collection(collectionPath).whereField("classID", in: chunk)
            let registration = firebase.addQueryListener(query, label: collectionPath) { [weak self] (periods: [Period]) in
                guard let self else { return }
                self.chunkResults[index] = periods
                var seen: Set<String> = []
                self.periods = self.chunkResults.values
                    .flatMap { $0 }
                    .filter { period in period.id.map { seen.insert($0).inserted } ?? true }
                    .sorted { $0.startTime < $1.startTime }
            }
            chunkListeners.append(registration)
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        chunkListeners.forEach { $0.remove() }
        chunkListeners = []
        chunkResults = [:]
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
