//
//  StepDiagnosisCard.swift
//  MathClass
//
//  The diagnosis of a wrong step as the teacher sees it: which skill
//  failed, how, the AI's note, and whether it is still the AI's proposal
//  or was reviewed. The teacher confirms it, changes the skill or removes
//  it: the statistics then use the teacher's version.
//

import SwiftUI

struct StepDiagnosisCard: View {
    let diagnosis: StepDiagnosis
    /// The corrected diagnosis, or nil to remove it.
    let onUpdate: (StepDiagnosis?) -> Void

    @State private var showingPicker = false
    @State private var query = ""

    private var reviewed: Bool { diagnosis.reviewedByTeacher == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Label(reviewed ? "Revu par l'enseignant".tr : "Proposé par l'IA".tr,
                      systemImage: reviewed ? "checkmark.seal" : "sparkles")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Menu {
                    if !reviewed {
                        Button("Confirmer".tr) {
                            var confirmed = diagnosis
                            confirmed.reviewedByTeacher = true
                            onUpdate(confirmed)
                        }
                    }
                    Button("Changer le savoir-faire…".tr) { showingPicker = true }
                    Button("Retirer ce diagnostic".tr, role: .destructive) { onUpdate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuIndicator(.hidden)
                .fixedSize()
            }
            if diagnosis.isConsequence {
                Text("Conséquence d'une erreur précédente (pas une nouvelle lacune).".tr)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                if let skillID = diagnosis.skillID, let skill = Taxonomy.shared.skill(skillID) {
                    Text("\(skill.competency.label) › \(skill.node.label)")
                        .font(.caption.bold())
                }
                if let type = diagnosis.errorType {
                    Text(SkillDiagnosis.errorTypeLabel(type)).font(.caption2).foregroundColor(.orange)
                }
                if let note = diagnosis.note {
                    Text(note).font(.caption).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.07)))
        .sheet(isPresented: $showingPicker) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Savoir-faire en cause".tr).font(.headline)
                    Spacer()
                    Button("Fermer".tr) { showingPicker = false }
                }
                TextField("Rechercher (ex. : développer, fractions, Pythagore)".tr, text: $query)
                    .textFieldStyle(.roundedBorder)
                List(Taxonomy.shared.search(query), id: \.id) { skill in
                    Button {
                        var changed = diagnosis
                        changed.skillID = skill.id
                        changed.reviewedByTeacher = true
                        if changed.isConsequence { changed.errorType = nil }
                        onUpdate(changed)
                        showingPicker = false
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(skill.node.label)
                            Text("\(skill.domain.label) › \(skill.competency.label)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .frame(minWidth: 460, minHeight: 480)
        }
    }
}
