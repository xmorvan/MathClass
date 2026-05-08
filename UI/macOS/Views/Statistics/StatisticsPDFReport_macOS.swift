//
//  StatisticsPDFReport_macOS.swift
//  MathClass
//
//  Render-to-PDF wrapper for the macOS statistics views. ImageRenderer
//  needs a concrete View it can rasterize off-screen, so we package
//  the same content the user sees on the Statistics tab into a fixed
//  letter-sized layout with a title and a footer for the timestamp.
//

import SwiftUI

struct StatisticsPDFReport_macOS: View {
    let title: String
    let generatedAt: Date
    let tab: StatisticsView_macOS.StatTab
    let viewModel: TeacherViewModel
    let submissions: [Submission]
    let classID: String?

    private let pageWidth: CGFloat = 612   // 8.5" @ 72 DPI
    private let pageHeight: CGFloat = 792  // 11"  @ 72 DPI

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2)
                    .bold()
                Text(generatedAt.formatted(date: .long, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Divider()

            Group {
                switch tab {
                case .perStudent:
                    StudentStatsListView_macOS(
                        viewModel: viewModel,
                        submissions: submissions,
                        classID: classID
                    )
                case .perExercise:
                    ExerciseStatsListView_macOS(
                        viewModel: viewModel,
                        submissions: submissions
                    )
                case .perClass:
                    ClassOverviewView_macOS(
                        viewModel: viewModel,
                        submissions: submissions,
                        classID: classID
                    )
                }
            }
        }
        .padding(36)
        .frame(width: pageWidth, height: pageHeight, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}
