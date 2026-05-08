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

    @State private var showScanner: Bool = false
    @State private var scanError: String?
    @State private var showScanError: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Bienvenue !".tr)
                .font(.largeTitle)
                .bold()

            Text("Entrez le code de votre classe\npour accéder à vos exercices.".tr)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Code input
            TextField("MX-XXXX".tr, text: $classCode)
                .textFieldStyle(.roundedBorder)
                .font(.system(.title2, design: .monospaced))
                .multilineTextAlignment(.center)
                .autocapitalization(.allCharacters)
                .disableAutocorrection(true)
                .frame(maxWidth: 220)
                .onSubmit {
                    if isCodeValid { onSubmit() }
                }

            // Scan button
            Button {
                showScanner = true
            } label: {
                Label("Scanner un QR code".tr, systemImage: "qrcode.viewfinder")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
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
                    Text("Valider".tr)
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
            Text("Demandez le code à votre professeur.\nIl ressemble à MX-XXXX.".tr)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)
        }
        .padding()
        .sheet(isPresented: $showScanner) {
            NavigationView {
                QRScannerView(
                    onScan: { raw in
                        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        // The QR may encode just the code (MX-XXXX) or a
                        // longer URL — extract the MX-XXXX substring if so.
                        if let match = trimmed.range(of: "MX-[A-Z0-9]{4}", options: .regularExpression) {
                            classCode = String(trimmed[match])
                        } else {
                            classCode = trimmed
                        }
                        showScanner = false
                        if isCodeValid { onSubmit() }
                    },
                    onError: { message in
                        scanError = message
                        showScanError = true
                        showScanner = false
                    }
                )
                .navigationTitle("Scanner un QR code".tr)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler".tr) { showScanner = false }
                    }
                }
            }
        }
        .alert("Erreur".tr, isPresented: $showScanError) {
            Button("OK".tr, role: .cancel) {}
        } message: {
            Text(scanError ?? "")
        }
    }

    private var isCodeValid: Bool {
        classCode.trimmingCharacters(in: .whitespacesAndNewlines).count >= 7
    }
}
