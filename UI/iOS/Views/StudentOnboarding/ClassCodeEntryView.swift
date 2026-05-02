//
//  ClassCodeEntryView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import SwiftUI

/// Step 1 of student onboarding: Enter the MX-XXXX class code.
/// Optionally scan a QR code of the class code.
struct ClassCodeEntryView: View {
    @Binding var classCode: String
    var isLookingUp: Bool
    var onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Bienvenue !")
                .font(.largeTitle)
                .bold()

            Text("Entrez le code de votre classe\npour accéder à vos exercices.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Code input
            TextField("MX-XXXX", text: $classCode)
                .textFieldStyle(.roundedBorder)
                .font(.system(.title2, design: .monospaced))
                .multilineTextAlignment(.center)
                .autocapitalization(.allCharacters)
                .disableAutocorrection(true)
                .frame(maxWidth: 220)
                .onSubmit {
                    if isCodeValid { onSubmit() }
                }

            // Validate button
            Button {
                onSubmit()
            } label: {
                if isLookingUp {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    Text("Valider")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isCodeValid ? Color.blue : Color.gray.opacity(0.4))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .disabled(!isCodeValid || isLookingUp)
            .frame(maxWidth: 260)

            Spacer()

            // Hint
            Text("Demandez le code à votre professeur.\nIl ressemble à MX-XXXX.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)
        }
        .padding()
    }

    private var isCodeValid: Bool {
        classCode.trimmingCharacters(in: .whitespacesAndNewlines).count >= 7
    }
}
