//
//  SkillTagsEditor.swift
//  MathClass
//
//  The skills of the taxonomy an exercise practises, as the teacher sees
//  and corrects them: remove one, add one by searching the taxonomy, or ask
//  the AI again. The diagnosis of the students' copies relies on them.
//

import SwiftUI

struct SkillTagsEditor: View {
    let exercise: Exercise
    /// Saves the exercise with new skill IDs.
    let onSave: ([String]) -> Void

    @State private var showingPicker = false
    @State private var query = ""

    private var skillIDs: [String] { exercise.skillIDs ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Savoir-faire".tr).font(.headline)
                Spacer()
                Button {
                    if let id = exercise.id {
                        SkillTaggingService.shared.tag(exerciseIDs: [id], force: true)
                    }
                } label: {
                    Label("Proposer avec l'IA".tr, systemImage: "sparkles")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                Button {
                    showingPicker = true
                } label: {
                    Label("Ajouter".tr, systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            if skillIDs.isEmpty {
                Text("Pas encore étiqueté : les savoir-faire sont proposés automatiquement à l'enregistrement.".tr)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            ForEach(skillIDs, id: \.self) { skillID in
                HStack(alignment: .top) {
                    if let skill = Taxonomy.shared.skill(skillID) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(skill.node.label).font(.callout)
                            Text("\(skill.domain.label) › \(skill.competency.label)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text(skillID).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        onSave(skillIDs.filter { $0 != skillID })
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Retirer".tr)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.07)))
            }
        }
        .sheet(isPresented: $showingPicker) {
            picker
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ajouter un savoir-faire".tr).font(.headline)
                Spacer()
                Button("Fermer".tr) { showingPicker = false }
            }
            TextField("Rechercher (ex. : développer, fractions, Pythagore)".tr, text: $query)
                .textFieldStyle(.roundedBorder)
            List(Taxonomy.shared.search(query), id: \.id) { skill in
                Button {
                    if !skillIDs.contains(skill.id) {
                        onSave(skillIDs + [skill.id])
                    }
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
                .disabled(skillIDs.contains(skill.id))
            }
        }
        .padding()
        .frame(minWidth: 460, minHeight: 480)
    }
}
