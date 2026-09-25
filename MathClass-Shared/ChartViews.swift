//
//  ChartViews.swift
//  MathClass
//
//  Shared chart components used by both the iPad Statistics tab and the
//  macOS Concept-Trend window. Apple's `Charts` framework requires
//  iOS 16+ / macOS 13+, both already the project's deployment targets.
//
//  Slice-8 chart parity (ISSUE-014 §1.4): the macOS ConceptTrendView used
//  to be the only consumer of `Charts`; the iPad Statistics tab rendered
//  text-only summaries, breaking the spec's "iPad parity on at least
//  trend + comparison". These components are the shared source of truth.
//

import SwiftUI
import Charts

// MARK: - Trend chart (per concept over time)

/// Per-concept success rate over the last 12 weeks. Renders a multi-series
/// line chart, one series per competency, with a percentage Y axis.
struct ConceptTrendChart: View {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Progression par compétence (12 semaines)".tr)
                .font(.title3)
                .bold()
            Text("Taux de réussite par compétence, semaine par semaine.".tr)
                .font(.caption)
                .foregroundColor(.secondary)
            if trendPoints.isEmpty {
                emptyHint
            } else {
                Chart(trendPoints, id: \.self) { point in
                    LineMark(
                        x: .value("Semaine", point.weekStart),
                        y: .value("Réussite", point.successRate)
                    )
                    .foregroundStyle(by: .value(
                        "Compétence",
                        competencyLabels[point.competencyID] ?? point.competencyID
                    ))
                    PointMark(
                        x: .value("Semaine", point.weekStart),
                        y: .value("Réussite", point.successRate)
                    )
                    .foregroundStyle(by: .value(
                        "Compétence",
                        competencyLabels[point.competencyID] ?? point.competencyID
                    ))
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

    private var emptyHint: some View {
        Text("Aucune donnée".tr)
            .foregroundColor(.secondary)
            .padding(.vertical, 24)
    }
}

// MARK: - AI error-taxonomy chart

/// Bar chart of AI-classified error categories across the supplied
/// submissions (sign_error, arithmetic, algebra, notation, conceptual).
struct ErrorTaxonomyChart: View {
    let submissions: [Submission]

    private let stats = StatisticsService.shared

    private var errorBreakdown: [(tag: String, count: Int)] {
        stats.errorTagBreakdown(submissions: submissions)
    }

    var body: some View {
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
                        x: .value("Catégorie", ErrorTagLabel.text(for: item.tag)),
                        y: .value("Occurrences", item.count)
                    )
                }
                .frame(height: 220)
            }
        }
    }
}

// MARK: - Co-occurrence list (X→Y)

/// Pairwise error co-occurrence: "students who make X also tend to make Y".
/// Rendered as a list of arrows; the visual bar chart variant is captured
/// by `ErrorTaxonomyChart`. The list shape stays compact in both layouts.
struct ErrorCoOccurrenceList: View {
    let submissions: [Submission]

    private let stats = StatisticsService.shared

    private var coOccurrence: [StatisticsService.ErrorCoOccurrence] {
        stats.errorCoOccurrence(submissions: submissions)
    }

    var body: some View {
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
                        Text(ErrorTagLabel.text(for: edge.from))
                            .font(.subheadline)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(6)
                        Image(systemName: "arrow.right")
                            .foregroundColor(.secondary)
                        Text(ErrorTagLabel.text(for: edge.to))
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

// MARK: - Co-occurrence heatmap

/// Heatmap variant of the X→Y co-occurrence relationship. Cell intensity
/// encodes the conditional probability `P(Y | X)`; bigger cells are more
/// reliable (more students contributing to the edge). The arrows-list
/// variant (`ErrorCoOccurrenceList`) stays available alongside for
/// teachers who prefer the ordered ranking.
struct ErrorCoOccurrenceHeatmap: View {
    let submissions: [Submission]

    private let stats = StatisticsService.shared

    private var edges: [StatisticsService.ErrorCoOccurrence] {
        stats.errorCoOccurrence(submissions: submissions)
    }

    private var axisTags: [String] {
        Array(Set(edges.flatMap { [$0.from, $0.to] })).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Carte des erreurs (X → Y)".tr)
                .font(.title3)
                .bold()
            Text("Lecture : si l'élève commet X, quelle est la probabilité qu'il commette aussi Y ?".tr)
                .font(.caption)
                .foregroundColor(.secondary)
            if edges.isEmpty {
                Text("Aucune donnée".tr)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 24)
            } else {
                Chart(edges, id: \.self) { edge in
                    RectangleMark(
                        x: .value("Si X", ErrorTagLabel.text(for: edge.from)),
                        y: .value("Alors Y", ErrorTagLabel.text(for: edge.to))
                    )
                    .foregroundStyle(by: .value("P(Y|X)", edge.conditional))
                }
                .chartXAxis { AxisMarks(values: axisTags) }
                .chartYAxis { AxisMarks(values: axisTags) }
                .chartForegroundStyleScale(range: Gradient(colors: [.yellow, .orange, .red]))
                .frame(height: max(200, CGFloat(axisTags.count * 36)))
            }
        }
    }
}

// MARK: - Vs-class-average chart

/// Per-competency comparison of one student's success rate against the
/// class mean. Two grouped bars per competency. Slice-8 #18.
struct VsClassAverageChart: View {
    let studentSuccessByCompetency: [String: Double]
    let classSuccessByCompetency: [String: Double]
    let competencyLabels: [String: String]

    private struct Row: Identifiable {
        let id: String
        let label: String
        let series: String
        let rate: Double
    }

    private var rows: [Row] {
        let allIDs = Set(studentSuccessByCompetency.keys)
            .union(classSuccessByCompetency.keys)
        let sortedIDs = allIDs.sorted {
            (competencyLabels[$0] ?? $0) < (competencyLabels[$1] ?? $1)
        }
        var out: [Row] = []
        for id in sortedIDs {
            let label = competencyLabels[id] ?? id
            if let s = studentSuccessByCompetency[id] {
                out.append(Row(id: "\(id)-s", label: label, series: "Élève".tr, rate: s))
            }
            if let c = classSuccessByCompetency[id] {
                out.append(Row(id: "\(id)-c", label: label, series: "Classe".tr, rate: c))
            }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Élève vs moyenne de la classe".tr)
                .font(.title3)
                .bold()
            Text("Taux de réussite de l'élève comparé à la moyenne de la classe par compétence.".tr)
                .font(.caption)
                .foregroundColor(.secondary)
            if rows.isEmpty {
                Text("Aucune donnée".tr)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 24)
            } else {
                Chart(rows) { row in
                    BarMark(
                        x: .value("Compétence", row.label),
                        y: .value("Réussite", row.rate)
                    )
                    .foregroundStyle(by: .value("Série", row.series))
                    .position(by: .value("Série", row.series))
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
}

// MARK: - Error tag labels

/// Readable names for the error categories returned by correct_submission
/// (the server sends language-neutral keys such as "sign_error").
enum ErrorTagLabel {
    static func text(for tag: String) -> String {
        switch tag {
        case "sign_error": return "Erreur de signe".tr
        case "arithmetic": return "Calcul".tr
        case "algebra": return "Algèbre".tr
        case "notation": return "Notation".tr
        case "conceptual": return "Compréhension".tr
        default: return tag.replacingOccurrences(of: "_", with: " ")
        }
    }
}
