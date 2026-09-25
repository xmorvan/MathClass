//
//  GradeOverrideMenu.swift
//  MathClass
//
//  Lets the teacher replace the automatic grade of a submission when the
//  correction got it wrong. Statistics read `finalResult`, so they follow.
//

import SwiftUI

struct GradeOverrideMenu: View {
    let submission: Submission
    let repository: SubmissionRepository

    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Menu {
                Button {
                    Task { await override(with: passedResult) }
                } label: {
                    Label("Marquer réussi".tr, systemImage: "checkmark.circle")
                }
                Button {
                    Task { await override(with: .failed) }
                } label: {
                    Label("Marquer échoué".tr, systemImage: "xmark.circle")
                }
            } label: {
                Label("Modifier la note".tr, systemImage: "pencil.circle")
            }
            .fixedSize()

            if submission.gradedByTeacher == true {
                Text("Note modifiée par l'enseignant".tr)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private var passedResult: SubmissionResult {
        submission.attemptNumber <= 1 ? .success1st : .success2nd
    }

    private func override(with result: SubmissionResult) async {
        guard let id = submission.id else { return }
        errorMessage = nil
        do {
            try await repository.overrideResult(submissionID: id, result: result)
        } catch {
            errorMessage = "Modification impossible. Vérifiez la connexion.".tr
        }
    }
}
