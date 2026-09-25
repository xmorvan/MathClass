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
            Text("Le mot de passe doit contenir :".tr)
                .font(.caption)
            Text("• Au moins 6 caractères".tr)
                .font(.caption)
            Text("• Au moins une lettre majuscule".tr)
                .font(.caption)
            Text("• Au moins un chiffre".tr)
                .font(.caption)
        }
        .foregroundColor(.secondary)
    }
    
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Connexion".tr)) {
                    TextField("Email".tr, text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)

                    SecureField("Mot de passe".tr, text: $viewModel.password)
                        .textContentType(.newPassword)

                    SecureField("Confirmer le mot de passe".tr, text: $viewModel.confirmPassword)
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

                Section(header: Text("Vos informations".tr)) {
                    TextField("Prénom".tr, text: $viewModel.firstName)
                        .textContentType(.givenName)
                    TextField("Nom".tr, text: $viewModel.lastName)
                        .textContentType(.familyName)
                }

                Section { passwordRequirements }
            }
            .navigationTitle("Inscription Professeur".tr)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler".tr) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Créer".tr) {
                        Task {
                            await viewModel.createAccount()
                        }
                    }
                    .disabled(!viewModel.isValid)
                }
            }
            .alert("Erreur".tr, isPresented: $viewModel.showError) {
                Button("OK".tr, role: .cancel) { }
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
