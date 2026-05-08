//
//  CreatePeriodView_macOS.swift
//  MathClass
//
//  Form for scheduling a new Period (one class hour) with one or more
//  Sessions. Replaces the legacy "create assignment" flow for the new
//  period/session model. Teachers pick a class, name + start/end of
//  the period, then add Sessions (each with mode A/B/C and a free-
//  order toggle).
//

import SwiftUI

struct CreatePeriodView_macOS: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: TeacherViewModel

    @State private var selectedClassID: String?
    @State private var name: String = ""
    @State private var startTime: Date = .now
    @State private var endTime: Date = .now.addingTimeInterval(3600)
    @State private var sessions: [SessionDraft] = [SessionDraft()]

    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false

    /// Form-side draft of a Session before it's persisted.
    struct SessionDraft: Identifiable {
        let id: UUID = UUID()
        var name: String = ""
        var mode: AssignmentMode = .differentiation
        var allowFreeOrder: Bool = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nouvelle séance".tr)
                .font(.title)

            Form {
                Section(header: Text("Classe".tr)) {
                    Picker("Classe".tr, selection: $selectedClassID) {
                        Text("Sélectionner une classe".tr).tag(nil as String?)
                        ForEach(viewModel.classes) { c in
                            Text(c.name).tag(c.id as String?)
                        }
                    }
                }

                Section(header: Text("Détails de la séance".tr)) {
                    TextField("Nom (ex : Cours du 9 mai)".tr, text: $name)
                    DatePicker("Début".tr, selection: $startTime)
                    DatePicker("Fin".tr, selection: $endTime, in: startTime...)
                }

                Section {
                    ForEach($sessions) { $draft in
                        sessionDraftRow(draft: $draft)
                    }

                    Button {
                        sessions.append(SessionDraft())
                    } label: {
                        Label("Ajouter un sous-créneau".tr, systemImage: "plus.circle")
                    }

                    Text("Une séance peut contenir plusieurs sous-créneaux ordonnés. Chaque sous-créneau a son propre mode de correction.".tr)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Sous-créneaux".tr)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Annuler".tr) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Créer la séance".tr)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid || isSaving)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 560, height: 640)
        .alert("Erreur".tr, isPresented: $showError) {
            Button("OK".tr, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func sessionDraftRow(draft: Binding<SessionDraft>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Nom du sous-créneau".tr, text: draft.name)
                if sessions.count > 1 {
                    Button {
                        sessions.removeAll { $0.id == draft.wrappedValue.id }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
            HStack {
                Picker("Mode".tr, selection: draft.mode) {
                    ForEach(AssignmentMode.allCases, id: \.self) { mode in
                        Label(mode.displayName, systemImage: mode.iconName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
            }
            Toggle("Ordre libre".tr, isOn: draft.allowFreeOrder)
        }
        .padding(.vertical, 4)
    }

    private var isValid: Bool {
        guard selectedClassID != nil else { return false }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard endTime > startTime else { return false }
        // Every session must have a name.
        return sessions.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    @MainActor
    private func save() async {
        guard let classID = selectedClassID else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let periodID = try await viewModel.createPeriod(
                classID: classID,
                name: name,
                startTime: startTime,
                endTime: endTime
            )
            for (index, draft) in sessions.enumerated() {
                _ = try await viewModel.createSession(
                    periodID: periodID,
                    name: draft.name,
                    mode: draft.mode,
                    allowFreeOrder: draft.allowFreeOrder,
                    order: index
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
