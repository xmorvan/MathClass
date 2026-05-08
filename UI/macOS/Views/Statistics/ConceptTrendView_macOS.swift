//
//  ConceptTrendView_macOS.swift
//  MathClass
//
//  Per-concept trend (line chart) and AI error-taxonomy roll-up (bar
//  chart) using Apple's Charts framework. Together they cover MVP
//  statistics #15 (error-pattern co-occurrence — see CoOccurrenceList),
//  #16 (AI taxonomy), #17 (per-concept progress over time), and #18
//  (vs-class-average — derived in StudentStatsDetailView).
//

import SwiftUI
import Charts

struct ConceptTrendView_macOS: View {
    let submissions: [Submission]
    let exerciseCompetencyMap: [String: [String]]
    let competencyLabels: [String: String]

    private let stats = StatisticsService.shared

    private var trendPoints: [StatisticsService.ConceptTrendPoint] {
        stats.conceptTrend(
            submissions: submissions,
            exerciseCompetencyMap: exerciseCompetencyMap
        )
    }

    private var errorBreakdown: [(tag: String, count: Int)] {
        stats.errorTagBreakdown(submissions: submissions)
    }

    private var coOccurrence: [StatisticsService.ErrorCoOccurrence] {
        stats.errorCoOccurrence(submissions: submissions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                trendChart
                Divider()
                errorTaxonomyChart
                Divider()
                coOccurrenceList
            }
            .padding()
        }
        .navigationTitle("Tendances".tr)
    }

    // MARK: - Trend chart (per concept over time)

    @ViewBuilder
    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Progression par compétence (12 semaines)".tr)
                .font(.title3)
                .bold()
            Text("Taux de réussite par compétence, semaine par semaine.".tr)
                .font(.caption)
                .foregroundColor(.secondary)
            if trendPoints.isEmpty {
                Text("Aucune donnée".tr)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 24)
            } else {
                Chart(trendPoints, id: \.self) { point in
                    LineMark(
                        x: .value("Semaine", point.weekStart),
                        y: .value("Réussite", point.successRate)
                    )
                    .foregroundStyle(by: .value("Compétence", competencyLabels[point.competencyID] ?? point.competencyID))
                    PointMark(
                        x: .value("Semaine", point.weekStart),
                        y: .value("Réussite", point.successRate)
                    )
                    .foregroundStyle(by: .value("Compétence", competencyLabels[point.competencyID] ?? point.competencyID))
                }
                .chartYAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v * 100))%")
                            }
                        }
                    }
                }
                .frame(height: 240)
            }
        }
    }

    // MARK: - Error-taxonomy chart

    @ViewBuilder
    private var errorTaxonomyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Types d'erreurs (IA)".tr)
                .font(.title3)
                .bold()
            Text("Catégorisation automatique des étapes erronées par l'IA.".tr)
                .font(.caption)
                .foregroundColor(.secondary)
            if errorBreakdown.isEmpty {
                Text("Aucune donnée".tr)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 24)
            } else {
                Chart(errorBreakdown, id: \.tag) { item in
                    BarMark(
                        x: .value("Catégorie", item.tag),
                        y: .value("Occurrences", item.count)
                    )
                }
                .frame(height: 220)
            }
        }
    }

    // MARK: - Co-occurrence list (X→Y)

    @ViewBuilder
    private var coOccurrenceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Erreurs liées (X → Y)".tr)
                .font(.title3)
                .bold()
            Text("Les élèves qui font l'erreur X font aussi souvent l'erreur Y.".tr)
                .font(.caption)
                .foregroundColor(.secondary)
            if coOccurrence.isEmpty {
                Text("Aucune donnée".tr)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 24)
            } else {
                ForEach(Array(coOccurrence.prefix(8)), id: \.self) { edge in
                    HStack {
                        Text(edge.from)
                            .font(.subheadline)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(6)
                        Image(systemName: "arrow.right")
                            .foregroundColor(.secondary)
                        Text(edge.to)
                            .font(.subheadline)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.red.opacity(0.15))
                            .cornerRadius(6)
                        Spacer()
                        Text("\(Int(edge.conditional * 100))% — \(edge.studentCount) él.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}
