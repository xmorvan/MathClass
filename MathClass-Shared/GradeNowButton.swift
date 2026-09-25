//
//  GradeNowButton.swift
//  MathClass
//
//  Lets the teacher grade a submission still waiting for its correction
//  (an evaluation's background grading runs on the student's iPad and
//  stops if the app is closed). The result arrives through the teacher's
//  submission listener.
//

import SwiftUI

struct GradeNowButton: View {
    let submissionID: String

    @State private var isGrading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button {
                Task { await grade() }
            } label: {
                if isGrading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Lancer la correction".tr, systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isGrading)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private func grade() async {
        isGrading = true
        errorMessage = nil
        do {
            try await CorrectionService.shared.gradeStoredSubmission(submissionID: submissionID)
        } catch {
            errorMessage = "La correction a échoué. Réessayez.".tr
        }
        isGrading = false
    }
}
