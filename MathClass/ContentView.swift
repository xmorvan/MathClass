//
//  ContentView.swift
//  MathClass
//
//  Created by Xavier Morvan on 18.11.2024.
//

import SwiftUI

/// Root view that routes to the appropriate interface based on authentication state.
/// - Teacher logged in via Firebase Auth → TeacherView
/// - Student session exists (class code + name) → StudentView
/// - Neither → RoleSelectionView
struct ContentView: View {
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var sessionManager = StudentSessionManager.shared

    var body: some View {
        Group {
            if authService.userRole == .teacher, authService.currentUser != nil {
                // Teacher is authenticated via Firebase Auth
                TeacherView()
            } else if sessionManager.sessionState == .loading {
                // Still restoring the keychain → Firestore session — show a
                // neutral splash so we don't flash RoleSelectionView while
                // the lookup is in flight (ISSUE-007).
                ProgressView("Chargement...")
            } else if sessionManager.isLoggedIn,
                      let student = sessionManager.currentStudent,
                      let studentID = student.id,
                      let classID = sessionManager.currentClassID {
                // Student has an active session (class code + name selection)
                StudentView(studentID: studentID, classID: classID)
            } else if authService.currentUser != nil {
                // Authenticated but role not yet loaded
                ProgressView("Chargement...")
            } else {
                // Not authenticated — show role selection
                RoleSelectionView()
            }
        }
    }
}
