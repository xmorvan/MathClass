//
//  TeacherSignUpView.swift
//  MathClass
//
//  Created by Xavier Morvan on 31.01.2025.
//

import SwiftUI

struct TeacherSignUpView: View {
    @StateObject private var viewModel = TeacherSignUpViewModel()
    @Environment(\.dismiss) private var dismiss
    
    private var passwordRequirements: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Le mot de passe doit contenir :")
                .font(.caption)
            Text("• Au moins 6 caractères")
                .font(.caption)
            Text("• Au moins une lettre majuscule")
                .font(.caption)
            Text("• Au moins un chiffre")
                .font(.caption)
        }
        .foregroundColor(.secondary)
    }
    
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Connexion")) {
                    TextField("Email", text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)

                    SecureField("Mot de passe", text: $viewModel.password)
                        .textContentType(.newPassword)

                    SecureField("Confirmer le mot de passe", text: $viewModel.confirmPassword)
                        .textContentType(.newPassword)
                    // NOTE: this view used to chain `.hidden()` and an
                    // `.onAppear` populating firstName/lastName onto the
                    // SecureField above. Because trailing modifiers attach to
                    // the previous expression, that hid the Confirm field
                    // outright (so passwordsMatch was always false) and the
                    // .onAppear was attached to a hidden view that may not
                    // fire. The default first/last names now live in
                    // TeacherSignUpViewModel.init(), and the field is back
                    // visible so the form is actually fillable.
                }

                Section { passwordRequirements }
            }
            .navigationTitle("Inscription Professeur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Créer") {
                        Task {
                            await viewModel.createAccount()
                        }
                    }
                    .disabled(!viewModel.isValid)
                }
            }
            .alert("Erreur", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage)
            }
            .onChange(of: viewModel.isAccountCreated) { oldValue, newValue in
                if newValue {
                    dismiss()
                }
            }
        }
    }
}
