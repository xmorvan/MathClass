//
//  ProfileLoadFailedView.swift
//  MathClass
//
//  Shown when a teacher is signed in but their `users/{uid}` profile can't
//  be loaded, instead of an endless loading spinner.
//

import SwiftUI

struct ProfileLoadFailedView: View {
    @ObservedObject var authService: AuthenticationService

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Impossible de charger votre profil".tr)
                .font(.title2)

            Text("Vérifiez votre connexion internet puis réessayez. Si le problème persiste, déconnectez-vous et reconnectez-vous.".tr)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 420)

            HStack(spacing: 12) {
                Button("Se déconnecter".tr) {
                    try? authService.signOut()
                }
                .buttonStyle(.bordered)

                Button("Réessayer".tr) {
                    Task { await authService.retryRoleLookup() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
