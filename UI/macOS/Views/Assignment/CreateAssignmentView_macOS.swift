//
//  CreateAssignmentView_macOS.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import SwiftUI

/// Assignment creation sheet for macOS.
/// Teacher selects: class, mode, exercises (filterable by chapter), and optionally
/// per-student/group targeting (differentiation mode).
struct CreateAssignmentView_macOS: View {
    @ObservedObject var viewModel: TeacherViewModel
    @ObservedObject var assignmentVM: AssignmentViewModel
    var onDismiss: () -> Void

    @State private var currentStep: CreationStep = .configure
    @State private var targetingExerciseIndex: Int?

    enum CreationStep {
        case configure
        case selectExercises
        case review
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with steps
            creationHeader

            Divider()

            // Content
            Group {
                switch currentStep {
                case .configure:
                    configureView
                case .selectExercises:
                    selectExercisesView
                case .review:
                    reviewView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation buttons
            navigationButtons
        }
    }

    // MARK: - Header

    private var creationHeader: some View {
        HStack(spacing: 24) {
            stepIndicator("1. " + "Configurer".tr, step: .configure)
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
            stepIndicator("2. " + "Exercices".tr, step: .selectExercises)
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
            stepIndicator("3. " + "Vérifier".tr, step: .review)
            Spacer()
        }
        .padding()
    }

    private func stepIndicator(_ title: String, step: CreationStep) -> some View {
        Text(title)
            .font(.headline)
            .foregroundColor(currentStep == step ? .accentColor : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(currentStep == step ? Color.accentColor.opacity(0.1) : Color.clear)
            )
    }

    // MARK: - Step 1: Configure

    private var configureView: some View {
        Form {
            Section("Classe".tr) {
                Picker("Classe".tr, selection: $assignmentVM.selectedClassID) {
                    Text("Sélectionner une classe".tr).tag(nil as String?)
                    ForEach(viewModel.classes) { classroom in
                        Text(classroom.name).tag(classroom.id as String?)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Nom".tr) {
                TextField("Nom du devoir (facultatif)".tr, text: $assignmentVM.assignmentName)
            }

            Section("Mode".tr) {
                Picker("Mode du devoir".tr, selection: $assignmentVM.selectedMode) {
                    ForEach(AssignmentMode.allCases, id: \.self) { mode in
                        Label(mode.displayName, systemImage: mode.iconName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                modeExplanation(for: assignmentVM.selectedMode)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func modeExplanation(for mode: AssignmentMode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch mode {
            case .differentiation:
                Label("Chaque élève/groupe reçoit des exercices ciblés.".tr, systemImage: "info.circle")
                Label("L'élève voit quelle étape est fausse.".tr, systemImage: "eye")
                Label("2e chance possible.".tr, systemImage: "arrow.counterclockwise")
            case .levels:
                Label("Progression automatique par niveau de difficulté.".tr, systemImage: "info.circle")
                Label("3 réussites consécutives = niveau suivant.".tr, systemImage: "arrow.up.circle")
                Label("2e chance possible (remet le compteur à zéro).".tr, systemImage: "arrow.counterclockwise")
            case .evaluation:
                Label("Mode contrôle : aucun feedback pour l'élève.".tr, systemImage: "info.circle")
                Label("Un seul essai.".tr, systemImage: "1.circle")
                Label("Le professeur voit les résultats.".tr, systemImage: "eye")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.vertical, 4)
    }

    // MARK: - Step 2: Select Exercises

    private var selectExercisesView: some View {
        HSplitView {
            // Left: Available exercises
            VStack(alignment: .leading, spacing: 0) {
                Text("Exercices disponibles".tr)
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Filters
                HStack {
                    TextField("Rechercher…".tr, text: $assignmentVM.searchText)
                        .textFieldStyle(.roundedBorder)

                    Picker("Chapitre".tr, selection: $assignmentVM.filterChapterID) {
                        Text("Tous".tr).tag(nil as String?)
                        ForEach(viewModel.chapters) { chapter in
                            Text(chapter.name).tag(chapter.id as String?)
                        }
                    }
                    .frame(width: 150)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)

                List {
                    ForEach(assignmentVM.filteredExercises) { exercise in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.displayTitle)
                                    .font(.body)
                                HStack(spacing: 2) {
                                    ForEach(1...5, id: \.self) { level in
                                        Image(systemName: level <= exercise.difficultyLevel ? "star.fill" : "star")
                                            .foregroundColor(level <= exercise.difficultyLevel ? .yellow : .gray.opacity(0.3))
                                            .font(.system(size: 10))
                                    }
                                }
                            }

                            Spacer()

                            let isSelected = assignmentVM.selectedExercises.contains { $0.exerciseID == exercise.id }
                            Button {
                                if !isSelected {
                                    assignmentVM.addExercise(exercise)
                                }
                            } label: {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                                    .foregroundColor(isSelected ? .green : .accentColor)
                            }
                            .buttonStyle(.plain)
                            .disabled(isSelected)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // Right: Selected exercises (reorderable)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Exercices sélectionnés".tr)
                        .font(.headline)
                    Spacer()
                    Text("\(assignmentVM.selectedExercises.count)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                if assignmentVM.selectedExercises.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Ajoutez des exercices depuis la liste de gauche".tr)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(Array(assignmentVM.selectedExercises.enumerated()), id: \.element.id) { index, selected in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\(selected.order).")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 24, alignment: .trailing)

                                    Text(selected.exerciseTitle)
                                        .font(.body)

                                    Spacer()

                                    // Target students button (differentiation mode)
                                    if assignmentVM.selectedMode == .differentiation {
                                        Button {
                                            targetingExerciseIndex = index
                                        } label: {
                                            let count = selected.targetStudentIDs?.count ?? 0
                                            Label(
                                                count > 0
                                                    ? LocalizationManager.shared.format(count > 1 ? "%@ élèves" : "%@ élève", String(count))
                                                    : "Tous".tr,
                                                systemImage: "person.2"
                                            )
                                            .font(.caption)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }

                                    Button {
                                        assignmentVM.removeExercise(at: IndexSet(integer: index))
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red.opacity(0.7))
                                    }
                                    .buttonStyle(.plain)
                                }

                                // Show targeted group name if set
                                if assignmentVM.selectedMode == .differentiation,
                                   let group = selected.targetGroupName {
                                    Text(group)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(4)
                                        .padding(.leading, 28)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .onMove { source, destination in
                            assignmentVM.moveExercise(from: source, to: destination)
                        }
                    }
                    .popover(item: $targetingExerciseIndex) { index in
                        StudentTargetingPopover(
                            students: assignmentVM.studentsInSelectedClass,
                            selectedIDs: assignmentVM.selectedExercises[safe: index]?.targetStudentIDs ?? [],
                            groupName: assignmentVM.selectedExercises[safe: index]?.targetGroupName ?? ""
                        ) { studentIDs, groupName in
                            assignmentVM.setTargetStudents(
                                exerciseIndex: index,
                                studentIDs: studentIDs.isEmpty ? nil : studentIDs,
                                groupName: groupName.isEmpty ? nil : groupName
                            )
                            targetingExerciseIndex = nil
                        }
                    }
                }
            }
            .frame(minWidth: 250)
        }
    }

    // MARK: - Step 3: Review

    private var reviewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Class
                VStack(alignment: .leading, spacing: 4) {
                    Text("Classe".tr)
                        .font(.headline)
                    if let classID = assignmentVM.selectedClassID {
                        Text(assignmentVM.className(for: classID))
                            .font(.body)
                    }
                }

                Divider()

                if !assignmentVM.assignmentName.trimmingCharacters(in: .whitespaces).isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nom".tr)
                            .font(.headline)
                        Text(assignmentVM.assignmentName)
                    }

                    Divider()
                }

                // Mode
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mode".tr)
                        .font(.headline)
                    HStack {
                        Image(systemName: assignmentVM.selectedMode.iconName)
                            .foregroundColor(assignmentVM.selectedMode.color)
                        Text(assignmentVM.selectedMode.displayName)
                    }
                }

                Divider()

                // Exercises
                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizationManager.shared.format("Exercices (%@)", String(assignmentVM.selectedExercises.count)))
                        .font(.headline)

                    ForEach(assignmentVM.selectedExercises) { selected in
                        HStack {
                            Text("\(selected.order).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(selected.exerciseTitle)
                            Spacer()
                            if let group = selected.targetGroupName {
                                Text(group)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }

                if let error = assignmentVM.error {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .padding()
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack {
            Button("Annuler".tr) {
                onDismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            if currentStep != .configure {
                Button("Précédent".tr) {
                    withAnimation {
                        switch currentStep {
                        case .selectExercises: currentStep = .configure
                        case .review: currentStep = .selectExercises
                        default: break
                        }
                    }
                }
                .buttonStyle(.bordered)
            }

            if currentStep == .review {
                Button {
                    Task {
                        await assignmentVM.createAssignment()
                        if assignmentVM.error == nil {
                            onDismiss()
                        }
                    }
                } label: {
                    if assignmentVM.isCreating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Créer le devoir".tr, systemImage: "plus.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    assignmentVM.isCreating
                        || assignmentVM.selectedExercises.isEmpty
                        || assignmentVM.selectedClassID == nil
                )
            } else {
                Button("Suivant".tr) {
                    withAnimation {
                        switch currentStep {
                        case .configure:
                            assignmentVM.loadStudentsForSelectedClass()
                            currentStep = .selectExercises
                        case .selectExercises:
                            currentStep = .review
                        default: break
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    (currentStep == .configure && assignmentVM.selectedClassID == nil)
                        || (currentStep == .selectExercises && assignmentVM.selectedExercises.isEmpty)
                )
            }
        }
        .padding()
    }
}

// MARK: - Student Targeting Popover

/// Popover for selecting which students should receive an exercise (differentiation mode).
struct StudentTargetingPopover: View {
    let students: [Student]
    @State var selectedIDs: [String]?
    @State var groupName: String
    var onSave: ([String], String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cibler des élèves".tr)
                .font(.headline)

            TextField("Nom du groupe (optionnel)".tr, text: $groupName)
                .textFieldStyle(.roundedBorder)

            Text("Sélectionnez les élèves (vide = tous) :".tr)
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(students) { student in
                        let isSelected = selectedIDs?.contains(student.id ?? "") ?? false
                        Button {
                            toggleStudent(student)
                        } label: {
                            HStack {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isSelected ? .blue : .secondary)
                                Text(student.sortName)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 200)

            HStack {
                Button("Réinitialiser".tr) {
                    selectedIDs = nil
                    groupName = ""
                }
                Spacer()
                Button("Appliquer".tr) {
                    onSave(selectedIDs ?? [], groupName)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 280)
    }

    private func toggleStudent(_ student: Student) {
        guard let studentID = student.id else { return }
        if selectedIDs == nil { selectedIDs = [] }
        if let index = selectedIDs?.firstIndex(of: studentID) {
            selectedIDs?.remove(at: index)
            if selectedIDs?.isEmpty == true { selectedIDs = nil }
        } else {
            selectedIDs?.append(studentID)
        }
    }
}

// MARK: - Helpers

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
