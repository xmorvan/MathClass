//
//  TeacherLoginView_iOS.swift
//  MathClass
//
//  Sign-in for an existing teacher account on iPad.
//

import SwiftUI

struct TeacherLoginView_iOS: View {
    @StateObject private var viewModel = TeacherLoginViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Connexion".tr)) {
                    TextField("Email".tr, text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    SecureField("Mot de passe".tr, text: $viewModel.password)
                        .textContentType(.password)
                }
            }
            .navigationTitle("Connexion Professeur".tr)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler".tr) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Se connecter".tr) {
                        Task { await viewModel.login() }
                    }
                    .disabled(!viewModel.isValid)
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
