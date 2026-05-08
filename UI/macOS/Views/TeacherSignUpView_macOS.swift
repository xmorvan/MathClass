//
//  TeacherSignUpView_macOS..swift
//  MathClass
//
//  Created by Xavier Morvan on 31.01.2025.
//

import SwiftUI

struct TeacherSignUpView_macOS: View {
    @StateObject private var viewModel = TeacherSignUpViewModel()
    @Environment(\.dismiss) private var dismiss
    
    private var passwordRequirements: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Le mot de passe doit contenir :".tr)
                .font(.caption)
                .padding(.bottom, 2)
            
            HStack {
                Image(systemName: viewModel.password.count >= 6 ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(viewModel.password.count >= 6 ? .green : .gray)
                Text("Au moins 6 caractères".tr)
                    .font(.caption)
            }
            
            HStack {
                Image(systemName: viewModel.password.contains(where: { $0.isUppercase }) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(viewModel.password.contains(where: { $0.isUppercase }) ? .green : .gray)
                Text("Au moins une majuscule".tr)
                    .font(.caption)
            }
            
            HStack {
                Image(systemName: viewModel.password.contains(where: { $0.isNumber }) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(viewModel.password.contains(where: { $0.isNumber }) ? .green : .gray)
                Text("Au moins un chiffre".tr)
                    .font(.caption)
            }
        }
        .foregroundColor(.secondary)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Inscription Professeur".tr)
                .font(.title)
            
            Form {
                TextField("Email".tr, text: $viewModel.email)
                    .textContentType(.emailAddress)
                
                SecureField("Mot de passe".tr, text: $viewModel.password)
                    .textContentType(.newPassword)
                
                passwordRequirements  // Ajouté ici
                
                SecureField("Confirmer le mot de passe".tr, text: $viewModel.confirmPassword)
                    .textContentType(.newPassword)
                
                TextField("Prénom".tr, text: $viewModel.firstName)
                    .textContentType(.givenName)
                
                TextField("Nom".tr, text: $viewModel.lastName)
                    .textContentType(.familyName)
            }
            .frame(width: 300)
            
            HStack {
                Button("Annuler".tr) {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Créer le compte".tr) {
                    Task {
                        await viewModel.createAccount()
                    }
                }
                .keyboardShortcut(.return)
                .disabled(!viewModel.isValid)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
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
