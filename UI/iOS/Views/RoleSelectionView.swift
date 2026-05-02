//
//  RoleSelectionView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.11.2024.
//

import SwiftUI

/// Initial screen: choose Teacher or Student role.
struct RoleSelectionView: View {
    @State private var showTeacherSignUp = false
    @State private var showStudentLogin = false

    var body: some View {
        VStack(spacing: 30) {
            Text("Sélectionnez votre profil")
                .font(.largeTitle)

            VStack(spacing: 20) {
                Button {
                    showTeacherSignUp = true
                } label: {
                    RoleSelectionButton(
                        title: "Professeur",
                        systemImage: "person.circle",
                        description: "Gérer les classes, créer et assigner des exercices"
                    )
                }

                Button {
                    showStudentLogin = true
                } label: {
                    RoleSelectionButton(
                        title: "Élève",
                        systemImage: "pencil.circle",
                        description: "Entrer le code classe pour accéder aux exercices"
                    )
                }
            }
        }
        .padding()
        .sheet(isPresented: $showTeacherSignUp) {
            TeacherSignUpView()
        }
        .sheet(isPresented: $showStudentLogin) {
            StudentLoginView()
        }
    }
}

/// Styled button for role selection.
struct RoleSelectionButton: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .frame(width: 60)

            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 2)
    }
}
