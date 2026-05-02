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
            Text("Le mot de passe doit contenir :")
                .font(.caption)
                .padding(.bottom, 2)
            
            HStack {
                Image(systemName: viewModel.password.count >= 6 ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(viewModel.password.count >= 6 ? .green : .gray)
                Text("Au moins 6 caractères")
                    .font(.caption)
            }
            
            HStack {
                Image(systemName: viewModel.password.contains(where: { $0.isUppercase }) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(viewModel.password.contains(where: { $0.isUppercase }) ? .green : .gray)
                Text("Au moins une majuscule")
                    .font(.caption)
            }
            
            HStack {
                Image(systemName: viewModel.password.contains(where: { $0.isNumber }) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(viewModel.password.contains(where: { $0.isNumber }) ? .green : .gray)
                Text("Au moins un chiffre")
                    .font(.caption)
            }
        }
        .foregroundColor(.secondary)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Inscription Professeur")
                .font(.title)
            
            Form {
                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                
                SecureField("Mot de passe", text: $viewModel.password)
                    .textContentType(.newPassword)
                
                passwordRequirements  // Ajouté ici
                
                SecureField("Confirmer le mot de passe", text: $viewModel.confirmPassword)
                    .textContentType(.newPassword)
                
                TextField("Prénom", text: $viewModel.firstName)
                    .textContentType(.givenName)
                
                TextField("Nom", text: $viewModel.lastName)
                    .textContentType(.familyName)
            }
            .frame(width: 300)
            
            HStack {
                Button("Annuler") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Créer le compte") {
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
