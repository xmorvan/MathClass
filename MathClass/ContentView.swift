//
//  ContentView.swift
//  MathClass
//
//  Created by Xavier Morvan on 18.11.2024.
//

import SwiftUI

/// Root view that routes to the appropriate interface based on authentication state.
/// - Teacher logged in via Firebase Auth (email/password) → TeacherView
/// - Student session exists (class code + name, anonymous Firebase account) → StudentView
/// - Neither → RoleSelectionView
struct ContentView: View {
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var sessionManager = StudentSessionManager.shared
    @StateObject private var localization = LocalizationManager.shared

    var body: some View {
        Group {
            if authService.userRole == .teacher, authService.isTeacherAccount {
                // Teacher is authenticated via Firebase Auth
                TeacherView()
            } else if sessionManager.sessionState == .loading {
                // Still restoring the keychain → Firestore session — show a
                // neutral splash so we don't flash RoleSelectionView while
                // the lookup is in flight (ISSUE-007).
                ProgressView("Chargement...".tr)
            } else if sessionManager.isLoggedIn,
                      let student = sessionManager.currentStudent,
                      let studentID = student.id,
                      let classID = sessionManager.currentClassID {
                // Student has an active session (class code + name selection)
                StudentView(studentID: studentID, classID: classID)
            } else if authService.isTeacherAccount {
                // Teacher authenticated but role not yet loaded. (An
                // anonymous account without a student session is a student
                // mid-onboarding: fall through to role selection.)
                ProgressView("Chargement...".tr)
            } else {
                // Not authenticated — show role selection
                RoleSelectionView()
            }
        }
        // Force the entire SwiftUI tree to rebuild when the user toggles
        // language so every `.tr` lookup re-evaluates immediately.
        .id(localization.language)
        .environmentObject(localization)
    }
}
