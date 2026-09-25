//
//  ConceptTrendView_macOS.swift
//  MathClass
//
//  Composes the shared chart components (in MathClass-Shared/ChartViews.swift)
//  into the macOS Tendances window. See ChartViews.swift for the actual
//  Charts-framework wiring.
//

import SwiftUI

struct ConceptTrendView_macOS: View {
    let submissions: [Submission]
    let exerciseCompetencyMap: [String: [String]]
    let competencyLabels: [String: String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ConceptTrendChart(
                    submissions: submissions,
                    exerciseCompetencyMap: exerciseCompetencyMap,
                    competencyLabels: competencyLabels
                )
                Divider()
                ErrorTaxonomyChart(submissions: submissions)
                Divider()
                ErrorCoOccurrenceHeatmap(submissions: submissions)
                Divider()
                ErrorCoOccurrenceList(submissions: submissions)
            }
            .padding()
        }
        .navigationTitle("Tendances".tr)
    }
}
