//
//  StudentNameSelectionView.swift
//  MathClassApp
//
//  Created by Xavier Morvan on 18.03.2026.
//

import SwiftUI

/// Step 2 of student onboarding: Select your name from the class student list.
struct StudentNameSelectionView: View {
    let classRoom: ClassRoom
    let students: [Student]
    var onSelectStudent: (Student) -> Void
    var onBack: () -> Void

    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text(classRoom.name)
                    .font(.title2)
                    .bold()

                Text("Code: \(classRoom.classCode)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Sélectionnez votre nom".tr)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            .padding()

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Rechercher…".tr, text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            // Student list
            List(filteredStudents) { student in
                Button {
                    onSelectStudent(student)
                } label: {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.title3)
                            .foregroundColor(.blue)

                        VStack(alignment: .leading) {
                            Text(student.fullName)
                                .font(.body)
                                .foregroundColor(.primary)
                        }

                        Spacer()

                        if student.deviceToken != nil {
                            HStack(spacing: 4) {
                                Image(systemName: "ipad")
                                    .font(.caption)
                                Text("lié".tr)
                                    .font(.caption2)
                            }
                            .foregroundColor(.orange)
                        }

                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            }

            // Back button
            Button {
                onBack()
            } label: {
                Label("Retour".tr, systemImage: "arrow.left")
                    .font(.callout)
            }
            .padding()
        }
    }

    private var filteredStudents: [Student] {
        let sorted = students.sorted { $0.lastName < $1.lastName }
        if searchText.isEmpty { return sorted }
        let query = searchText.lowercased()
        return sorted.filter {
            $0.fullName.lowercased().contains(query)
        }
    }
}
