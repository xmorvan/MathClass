//
//  ContentView_macOS.swift
//  MathClass-macOS
//
//  Created by Xavier Morvan on 23.01.2025.
//

import SwiftUI

/// Root view for the macOS app. Teacher-only — routes to auth or teacher dashboard.
struct ContentView_macOS: View {
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var localization = LocalizationManager.shared
    @State private var showTeacherSignUp = false
    @State private var showLogin = false

    var body: some View {
        Group {
            if authService.userRole == .teacher {
                TeacherView_macOS()
            } else if authService.isTeacherAccount {
                ProgressView("Chargement...".tr)
            } else {
                teacherAuthView
            }
        }
        .id(localization.language)
        .environmentObject(localization)
    }

    private var teacherAuthView: some View {
        VStack(spacing: 30) {
            Image(systemName: "person.circle")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("MathClass pour Professeurs".tr)
                .font(.title)
                .bold()

            VStack(spacing: 15) {
                Button("Se connecter".tr) {
                    showLogin = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Créer un compte".tr) {
                    showTeacherSignUp = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .frame(width: 200)
        }
        .frame(width: 400, height: 300)
        .sheet(isPresented: $showTeacherSignUp) {
            TeacherSignUpView_macOS()
        }
        .sheet(isPresented: $showLogin) {
            TeacherLoginView_macOS()
        }
    }
}

// MARK: - Teacher Login View

struct TeacherLoginView_macOS: View {
    @StateObject private var viewModel = TeacherLoginViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Connexion Professeur".tr)
                .font(.title)

            Form {
                TextField("Email".tr, text: $viewModel.email)
                    .textContentType(.emailAddress)

                SecureField("Mot de passe".tr, text: $viewModel.password)
                    .textContentType(.password)
            }
            .frame(width: 300)

            HStack {
                Button("Annuler".tr) {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Se connecter".tr) {
                    Task { await viewModel.login() }
                }
                .keyboardShortcut(.return)
                .disabled(!viewModel.isValid)
            }
        }
        .padding()
        .frame(width: 400, height: 250)
        .alert("Erreur".tr, isPresented: $viewModel.showError) {
            Button("OK".tr, role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .onChange(of: viewModel.isLoggedIn) { _, newValue in
            if newValue { dismiss() }
        }
    }
}

// MARK: - Teacher Login ViewModel

class TeacherLoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var isLoggedIn = false

    var isValid: Bool {
        !email.isEmpty && !password.isEmpty && email.contains("@")
    }

    @MainActor
    func login() async {
        do {
            try await AuthenticationService.shared.signIn(email: email, password: password)
            self.isLoggedIn = true
        } catch {
            self.errorMessage = error.localizedDescription
            self.showError = true
        }
    }
}
