//
//  GroupRepository.swift
//  MathClass
//
//  CRUD + listener for student groups under a class.
//  Path: `classes/{classID}/groups/{groupID}`.
//

import Foundation
import FirebaseFirestore
import Combine

@MainActor
final class GroupRepository: ObservableObject {
    @Published private(set) var groups: [StudentGroup] = []
    @Published private(set) var isLoading: Bool = false
    @Published var error: String?

    private let firebase = FirebaseService.shared
    private var listener: ListenerRegistration?

    deinit {
        listener?.remove()
    }

    private func collectionPath(classID: String) -> String {
        "classes/\(classID)/groups"
    }

    func startListening(classID: String) {
        listener?.remove()
        listener = firebase.addCollectionListener(
            collection: collectionPath(classID: classID)
        ) { [weak self] (groups: [StudentGroup]) in
            self?.groups = groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    func createGroup(_ group: StudentGroup) async throws -> String {
        let docRef = try await firebase.createDocument(
            group,
            in: collectionPath(classID: group.classID)
        )
        return docRef.documentID
    }

    func updateGroup(_ group: StudentGroup) async throws {
        guard let id = group.id else { return }
        try await firebase.updateDocument(
            group,
            in: collectionPath(classID: group.classID),
            documentID: id
        )
    }

    func deleteGroup(id: String, classID: String) async throws {
        try await firebase.deleteDocument(
            from: collectionPath(classID: classID),
            documentID: id
        )
    }

    func getGroups(classID: String) async throws -> [StudentGroup] {
        let groups: [StudentGroup] = try await firebase.getDocuments(
            from: collectionPath(classID: classID)
        )
        return groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Add a student to a group. Updates both the group's `studentIDs`
    /// array and the student's `groupID` denormalization in a logical
    /// transaction. (Firestore writes aren't strictly atomic across
    /// docs here — the student's `groupID` is a hint, the group's
    /// `studentIDs` is source of truth.)
    func addStudent(studentID: String, toGroup groupID: String, classID: String) async throws {
        var group: StudentGroup = try await firebase.getDocument(
            groupID,
            from: collectionPath(classID: classID)
        )
        if !group.studentIDs.contains(studentID) {
            group.studentIDs.append(studentID)
            try await updateGroup(group)
        }
        try await firebase.updateFields(
            ["groupID": groupID],
            in: "classes/\(classID)/students",
            documentID: studentID
        )
    }

    func removeStudent(studentID: String, fromGroup groupID: String, classID: String) async throws {
        var group: StudentGroup = try await firebase.getDocument(
            groupID,
            from: collectionPath(classID: classID)
        )
        group.studentIDs.removeAll { $0 == studentID }
        try await updateGroup(group)
        try await firebase.updateFields(
            ["groupID": FieldValue.delete()],
            in: "classes/\(classID)/students",
            documentID: studentID
        )
    }
}
