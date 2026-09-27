//
//  SkillTaggingService.swift
//  MathClass
//
//  Asks the `tag_exercises` Cloud Function to tag exercises with the skills
//  of the taxonomy they practise. Fire and forget: the tags arrive through
//  the exercise listener; a failure only leaves an exercise untagged.
//

import Foundation
import FirebaseFunctions

final class SkillTaggingService {

    static let shared = SkillTaggingService()

    private let functions = Functions.functions(region: "europe-west6")

    private init() {}

    func tag(exerciseIDs: [String], force: Bool = false) {
        let ids = Array(exerciseIDs.prefix(20))
        guard !ids.isEmpty else { return }
        let callable = functions.httpsCallable("tag_exercises")
        callable.timeoutInterval = 60
        Task {
            do {
                _ = try await callable.call(["exerciseIDs": ids, "force": force])
            } catch {
                print("Étiquetage des exercices échoué: \(error.localizedDescription)")
            }
        }
    }
}
