//
//  FirebaseService.swift
//  MathClass
//
//  Created by Xavier Morvan on 29.01.2025.
//

import FirebaseAuth
import FirebaseFirestore

/// Centralized Firestore operations service.
/// All repositories use this for CRUD and real-time listeners.
class FirebaseService {
    static let shared = FirebaseService()
    let db = Firestore.firestore()

    private init() {}

    // MARK: - Document Management

    /// Create or overwrite a document. If `documentID` is nil, Firestore auto-generates one.
    /// Returns the DocumentReference of the created/updated document.
    func createDocument<T: Encodable>(
        _ data: T,
        in collection: String,
        documentID: String? = nil
    ) async throws -> DocumentReference {
        if let documentID = documentID {
            let docRef = db.collection(collection).document(documentID)
            let encoded = try Firestore.Encoder().encode(data)
            try await docRef.setData(encoded)
            return docRef
        } else {
            let encoded = try Firestore.Encoder().encode(data)
            return try await db.collection(collection).addDocument(data: encoded)
        }
    }

    /// Fetch a single document by ID, decoded using Firestore's snapshot decoder
    /// which correctly populates `@DocumentID` fields.
    func getDocument<T: Decodable>(
        _ id: String,
        from collection: String
    ) async throws -> T {
        let snapshot = try await db.collection(collection).document(id).getDocument()
        guard snapshot.exists else {
            throw FirebaseServiceError.documentNotFound(collection: collection, id: id)
        }
        return try snapshot.data(as: T.self)
    }

    /// Update a document using merge, preserving fields not included in the data.
    func updateDocument<T: Encodable>(
        _ data: T,
        in collection: String,
        documentID: String
    ) async throws {
        let docRef = db.collection(collection).document(documentID)
        let encoded = try Firestore.Encoder().encode(data)
        try await docRef.setData(encoded, merge: true)
    }

    /// Delete a document by ID.
    func deleteDocument(
        from collection: String,
        documentID: String
    ) async throws {
        try await db.collection(collection).document(documentID).delete()
    }

    /// Partial-update helper that accepts raw Firestore values such as
    /// `FieldValue.delete()` or `FieldValue.serverTimestamp()`. Use this
    /// instead of reaching into `db` directly from a repository — see
    /// CLAUDE.md ("never access `db` directly").
    func updateFields(
        _ fields: [String: Any],
        in collection: String,
        documentID: String
    ) async throws {
        try await db.collection(collection).document(documentID).updateData(fields)
    }

    // MARK: - Collection Queries

    /// Fetch all documents from a collection.
    func getDocuments<T: Decodable>(from collection: String) async throws -> [T] {
        let snapshot = try await db.collection(collection).getDocuments()
        return try snapshot.documents.map { try $0.data(as: T.self) }
    }

    /// Fetch documents matching a single field equality condition.
    func queryDocuments<T: Decodable>(
        from collection: String,
        whereField field: String,
        isEqualTo value: Any
    ) async throws -> [T] {
        let snapshot = try await db.collection(collection)
            .whereField(field, isEqualTo: value)
            .getDocuments()
        return try snapshot.documents.map { try $0.data(as: T.self) }
    }

    /// Fetch documents matching a field-in-array condition.
    func queryDocuments<T: Decodable>(
        from collection: String,
        whereField field: String,
        in values: [Any]
    ) async throws -> [T] {
        guard !values.isEmpty else { return [] }
        let snapshot = try await db.collection(collection)
            .whereField(field, in: values)
            .getDocuments()
        return try snapshot.documents.map { try $0.data(as: T.self) }
    }

    /// Fetch the documents matching a query built by the caller (compound
    /// filters, e.g. the per-caller scoping `SubmissionRepository` applies).
    func getDocuments<T: Decodable>(matching query: Query) async throws -> [T] {
        let snapshot = try await query.getDocuments()
        return try snapshot.documents.map { try $0.data(as: T.self) }
    }

    // MARK: - Batch writes

    /// Atomically write multiple documents to the same collection in a
    /// single Firestore batch. Use for bulk imports (paste roster, demo
    /// seed) — a 30-row paste used to fire 30 sequential writes (one
    /// network round-trip each); a batch is one round-trip total.
    /// Firestore caps a batch at 500 ops; the helper chunks past that.
    func createDocuments<T: Encodable>(
        _ items: [T],
        in collection: String,
        idFor: (T) -> String? = { _ in nil }
    ) async throws {
        guard !items.isEmpty else { return }
        for chunk in items.chunked(into: 450) {
            let batch = db.batch()
            for item in chunk {
                let docRef = idFor(item).map { db.collection(collection).document($0) }
                    ?? db.collection(collection).document()
                let encoded = try Firestore.Encoder().encode(item)
                batch.setData(encoded, forDocument: docRef)
            }
            try await batch.commit()
        }
    }

    // MARK: - Real-time Listeners

    /// Listen to a query built by the caller. `label` only appears in logs.
    func addQueryListener<T: Decodable>(
        _ query: Query,
        label: String,
        onUpdate: @escaping ([T]) -> Void
    ) -> ListenerRegistration {
        return query.addSnapshotListener { snapshot, error in
            if let error = error {
                print("Erreur écoute collection \(label): \(error.localizedDescription)")
                onUpdate([])
                return
            }
            guard let documents = snapshot?.documents else {
                onUpdate([])
                return
            }
            do {
                let decoded = try documents.map { try $0.data(as: T.self) }
                onUpdate(decoded)
            } catch {
                print("Erreur décodage collection \(label): \(error.localizedDescription)")
                onUpdate([])
            }
        }
    }

    /// Listen to changes on a single document.
    ///
    /// `onError` (optional) fires once per listener error and once on
    /// decode failure. Callers that want to surface listener failures
    /// to the UI (e.g. a "permission denied" badge on a read-restricted
    /// collection) pass a closure; the default no-op preserves the prior
    /// behaviour of silently calling `onUpdate(nil)`.
    func addDocumentListener<T: Decodable>(
        documentID: String,
        in collection: String,
        onUpdate: @escaping (T?) -> Void,
        onError: ((Error) -> Void)? = nil
    ) -> ListenerRegistration {
        let docRef = db.collection(collection).document(documentID)
        return docRef.addSnapshotListener { snapshot, error in
            if let error = error {
                print("Erreur écoute document \(collection)/\(documentID): \(error.localizedDescription)")
                onError?(error)
                onUpdate(nil)
                return
            }
            guard let snapshot = snapshot, snapshot.exists else {
                onUpdate(nil)
                return
            }
            do {
                let decoded = try snapshot.data(as: T.self)
                onUpdate(decoded)
            } catch {
                print("Erreur décodage document \(collection)/\(documentID): \(error.localizedDescription)")
                onError?(error)
                onUpdate(nil)
            }
        }
    }

    /// Listen to changes on a collection query filtered by a single field.
    /// `onError` (optional) surfaces listener failure to the caller. See
    /// `addDocumentListener` for the rationale.
    func addQueryListener<T: Decodable>(
        from collection: String,
        whereField field: String,
        isEqualTo value: Any,
        onUpdate: @escaping ([T]) -> Void,
        onError: ((Error) -> Void)? = nil
    ) -> ListenerRegistration {
        let query = db.collection(collection).whereField(field, isEqualTo: value)
        return query.addSnapshotListener { snapshot, error in
            if let error = error {
                print("Erreur écoute collection \(collection): \(error.localizedDescription)")
                onError?(error)
                onUpdate([])
                return
            }
            guard let documents = snapshot?.documents else {
                onUpdate([])
                return
            }
            do {
                let decoded = try documents.map { try $0.data(as: T.self) }
                onUpdate(decoded)
            } catch {
                print("Erreur décodage collection \(collection): \(error.localizedDescription)")
                onError?(error)
                onUpdate([])
            }
        }
    }

    /// Listen to all documents in a collection (no filter).
    /// `onError` (optional) surfaces listener failure to the caller. See
    /// `addDocumentListener` for the rationale.
    func addCollectionListener<T: Decodable>(
        collection: String,
        onUpdate: @escaping ([T]) -> Void,
        onError: ((Error) -> Void)? = nil
    ) -> ListenerRegistration {
        return db.collection(collection).addSnapshotListener { snapshot, error in
            if let error = error {
                print("Erreur écoute collection \(collection): \(error.localizedDescription)")
                onError?(error)
                onUpdate([])
                return
            }
            guard let documents = snapshot?.documents else {
                onUpdate([])
                return
            }
            do {
                let decoded = try documents.map { try $0.data(as: T.self) }
                onUpdate(decoded)
            } catch {
                print("Erreur décodage collection \(collection): \(error.localizedDescription)")
                onError?(error)
                onUpdate([])
            }
        }
    }
}

// MARK: - Errors

enum FirebaseServiceError: LocalizedError {
    case documentNotFound(collection: String, id: String)

    var errorDescription: String? {
        switch self {
        case .documentNotFound(let collection, let id):
            return "Document introuvable : \(collection)/\(id)"
        }
    }
}
