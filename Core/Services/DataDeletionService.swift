//
//  DataDeletionService.swift
//  MathClass
//
//  Cascade deletions run server-side (`delete_class`, `delete_account`
//  Cloud Functions): Firestore does not delete subcollections, and the
//  security rules don't let a client wipe a class's submissions or images.
//

import Foundation
import FirebaseFunctions

final class DataDeletionService {
    static let shared = DataDeletionService()

    private let functions: Functions = Functions.functions(region: "europe-west6")

    private init() {}

    /// Delete a class the current teacher owns, with its students, groups,
    /// chapters, assignments, periods, submissions and handwriting images.
    func deleteClass(id: String) async throws {
        _ = try await functions.httpsCallable("delete_class").call(["classID": id])
    }

    /// Delete the current teacher's account and all their data. The caller
    /// signs out afterwards.
    func deleteAccount() async throws {
        _ = try await functions.httpsCallable("delete_account").call()
    }
}
