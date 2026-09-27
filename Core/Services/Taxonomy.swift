//
//  Taxonomy.swift
//  MathClass
//
//  The skill taxonomy (domaine > compétence > savoir-faire) bundled with the
//  app, the same file the Cloud Functions use (built by
//  tools/build_taxonomy.py). Exercises carry skill IDs and each wrong step
//  of a copy is tied to the skill that failed: the teacher's diagnosis
//  reads both through this.
//

import Foundation

struct TaxonomyNode: Decodable, Hashable {
    let id: String
    let fr: String
    let en: String

    /// Label in the app's language.
    var label: String {
        LocalizationManager.shared.language == .en ? en : fr
    }
}

final class Taxonomy {

    struct Skill: Hashable {
        let node: TaxonomyNode
        let competency: TaxonomyNode
        let domain: TaxonomyNode
        var id: String { node.id }
    }

    static let shared = Taxonomy()

    private(set) var domains: [TaxonomyNode] = []
    private(set) var competenciesByDomain: [String: [TaxonomyNode]] = [:]
    private(set) var skillsByCompetency: [String: [Skill]] = [:]
    private var skillsByID: [String: Skill] = [:]
    private var nodesByID: [String: TaxonomyNode] = [:]

    private struct File: Decodable {
        struct Competency: Decodable {
            let id: String, fr: String, en: String
            let skills: [TaxonomyNode]
        }
        struct Domain: Decodable {
            let id: String, fr: String, en: String
            let competencies: [Competency]
        }
        let domains: [Domain]
    }

    init(data: Data? = nil) {
        let data = data ?? Bundle.main.url(forResource: "Taxonomy", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
        guard let data, let file = try? JSONDecoder().decode(File.self, from: data) else {
            print("Taxonomy.json missing or unreadable")
            return
        }
        for domain in file.domains {
            let domainNode = TaxonomyNode(id: domain.id, fr: domain.fr, en: domain.en)
            domains.append(domainNode)
            nodesByID[domain.id] = domainNode
            for competency in domain.competencies {
                let competencyNode = TaxonomyNode(id: competency.id, fr: competency.fr, en: competency.en)
                competenciesByDomain[domain.id, default: []].append(competencyNode)
                nodesByID[competency.id] = competencyNode
                for skill in competency.skills {
                    let entry = Skill(node: skill, competency: competencyNode, domain: domainNode)
                    skillsByCompetency[competency.id, default: []].append(entry)
                    skillsByID[skill.id] = entry
                    nodesByID[skill.id] = skill
                }
            }
        }
    }

    func skill(_ id: String) -> Skill? { skillsByID[id] }

    /// Domain, competency or skill.
    func node(_ id: String) -> TaxonomyNode? { nodesByID[id] }

    var allSkills: [Skill] {
        domains.flatMap { domain in
            (competenciesByDomain[domain.id] ?? []).flatMap { skillsByCompetency[$0.id] ?? [] }
        }
    }

    /// Skills whose label, competency or domain contains the text.
    func search(_ text: String) -> [Skill] {
        let query = text.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        guard !query.isEmpty else { return allSkills }
        return allSkills.filter { skill in
            [skill.node.label, skill.competency.label, skill.domain.label]
                .joined(separator: " ")
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .contains(query)
        }
    }
}
