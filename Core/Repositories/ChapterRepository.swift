//
//  ChapterRepository.swift
//  MathClass
//
//  Created by Xavier Morvan on 18.03.2026.
//

import Foundation
import FirebaseFirestore
import Combine

/// Repository for Chapter and Competency entities.
/// Manages CRUD for `classes/{classID}/chapters/{chapterID}`
/// and `classes/{classID}/chapters/{chapterID}/competencies/{competencyID}`.
@MainActor
class ChapterRepository: ObservableObject {
    @Published private(set) var chapters: [Chapter] = []
    @Published private(set) var competencies: [String: [Competency]] = [:] // chapterID -> competencies
    @Published var error: String?
    /// Competency labels across every class of the teacher (id -> label).
    /// Exercises are shared between classes, so their tags can point to
    /// another class's competencies; this keeps statistics readable.
    @Published private(set) var competencyLabels: [String: String] = [:]

    private let firebase = FirebaseService.shared
    private var chaptersListener: ListenerRegistration?
    private var competencyListeners: [String: ListenerRegistration] = [:]

    deinit {
        chaptersListener?.remove()
        competencyListeners.values.forEach { $0.remove() }
    }

    // MARK: - Collection Paths

    private func chaptersPath(classID: String) -> String {
        "classes/\(classID)/chapters"
    }

    private func competenciesPath(classID: String, chapterID: String) -> String {
        "classes/\(classID)/chapters/\(chapterID)/competencies"
    }

    // MARK: - Chapters Listener

    func startListening(classID: String) {
        chaptersListener?.remove()
        competencyListeners.values.forEach { $0.remove() }
        competencyListeners.removeAll()

        let path = chaptersPath(classID: classID)
        chaptersListener = firebase.addCollectionListener(collection: path) { [weak self] (chapters: [Chapter]) in
            self?.chapters = chapters.sorted { $0.order < $1.order }
            // Set up competency listeners for each chapter
            for chapter in chapters {
                guard let chapterID = chapter.id else { continue }
                self?.startCompetencyListener(classID: classID, chapterID: chapterID)
            }
        }
    }

    func stopListening() {
        chaptersListener?.remove()
        chaptersListener = nil
        competencyListeners.values.forEach { $0.remove() }
        competencyListeners.removeAll()
    }

    private func startCompetencyListener(classID: String, chapterID: String) {
        // Don't add duplicate listeners
        guard competencyListeners[chapterID] == nil else { return }

        let path = competenciesPath(classID: classID, chapterID: chapterID)
        let listener = firebase.addCollectionListener(collection: path) { [weak self] (competencies: [Competency]) in
            self?.competencies[chapterID] = competencies
            for competency in competencies {
                if let id = competency.id { self?.competencyLabels[id] = competency.label }
            }
        }
        competencyListeners[chapterID] = listener
    }

    // MARK: - Chapter CRUD

    func createChapter(_ chapter: Chapter, classID: String) async throws -> String {
        let docRef = try await firebase.createDocument(
            chapter,
            in: chaptersPath(classID: classID)
        )
        return docRef.documentID
    }

    func updateChapter(_ chapter: Chapter, classID: String) async throws {
        guard let id = chapter.id else { return }
        try await firebase.updateDocument(
            chapter,
            in: chaptersPath(classID: classID),
            documentID: id
        )
    }

    func deleteChapter(id: String, classID: String) async throws {
        try await firebase.deleteDocument(
            from: chaptersPath(classID: classID),
            documentID: id
        )
        // Clean up competency listener
        competencyListeners[id]?.remove()
        competencyListeners.removeValue(forKey: id)
        competencies.removeValue(forKey: id)
    }

    // MARK: - Competency CRUD

    func createCompetency(_ competency: Competency, classID: String, chapterID: String) async throws -> String {
        let docRef = try await firebase.createDocument(
            competency,
            in: competenciesPath(classID: classID, chapterID: chapterID)
        )
        return docRef.documentID
    }

    func updateCompetency(_ competency: Competency, classID: String, chapterID: String) async throws {
        guard let id = competency.id else { return }
        try await firebase.updateDocument(
            competency,
            in: competenciesPath(classID: classID, chapterID: chapterID),
            documentID: id
        )
    }

    func deleteCompetency(id: String, classID: String, chapterID: String) async throws {
        try await firebase.deleteDocument(
            from: competenciesPath(classID: classID, chapterID: chapterID),
            documentID: id
        )
    }

    /// Fill `competencyLabels` with the competencies of every given class
    /// (one-shot). Classes that fail to load are skipped.
    func loadCompetencyLabels(classIDs: [String]) async {
        for classID in classIDs {
            guard let chapters: [Chapter] = try? await firebase.getDocuments(from: chaptersPath(classID: classID)) else { continue }
            for chapter in chapters {
                guard let chapterID = chapter.id,
                      let competencies = try? await getCompetencies(classID: classID, chapterID: chapterID) else { continue }
                for competency in competencies {
                    if let id = competency.id { competencyLabels[id] = competency.label }
                }
            }
        }
    }

    /// Human-readable label for a competency ID from any of the teacher's
    /// classes; falls back to the ID itself.
    func competencyLabel(for competencyID: String) -> String {
        competencyLabels[competencyID] ?? competencyID
    }

    /// Get all competencies for a given chapter (one-shot, not real-time).
    func getCompetencies(classID: String, chapterID: String) async throws -> [Competency] {
        try await firebase.getDocuments(
            from: competenciesPath(classID: classID, chapterID: chapterID)
        )
    }
}
