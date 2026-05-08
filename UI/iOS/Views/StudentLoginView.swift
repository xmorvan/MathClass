//
//  StudentLoginView.swift
//  MathClass
//
//  Created by Xavier Morvan on 22.11.2024.
//

import SwiftUI

/// Student onboarding flow:
/// 1. Enter class code (MX-XXXX) via ClassCodeEntryView
/// 2. Select name from class student list via StudentNameSelectionView
/// 3. Session saved to Keychain via StudentOnboardingViewModel
struct StudentLoginView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = StudentOnboardingViewModel()

    var body: some View {
        NavigationView {
            VStack {
                switch viewModel.step {
                case .enterCode:
                    ClassCodeEntryView(
                        classCode: $viewModel.classCode,
                        isLookingUp: viewModel.isLookingUp,
                        onSubmit: { viewModel.lookupClass() }
                    )

                case .selectName:
                    if let classRoom = viewModel.matchedClass {
                        StudentNameSelectionView(
                            classRoom: classRoom,
                            students: viewModel.studentsInClass,
                            onSelectStudent: { student in
                                viewModel.selectStudent(student)
                                dismiss()
                            },
                            onBack: { viewModel.goBack() }
                        )
                    }
                }
            }
            .navigationTitle("Connexion Élève".tr)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler".tr) { dismiss() }
                }
            }
            .alert("Erreur".tr, isPresented: $viewModel.showError) {
                Button("OK".tr, role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }
}
