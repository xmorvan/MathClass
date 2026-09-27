//
//  SkillDiagnosisTests.swift
//  MathClassTests
//
//  The teacher's diagnosis, skill by skill: "En Développer, Zoé ne sait
//  pas développer un produit de trois facteurs".
//

import XCTest
@testable import MathClass

final class SkillDiagnosisTests: XCTestCase {

    private let threeFactors = "litteral.developper.trois-facteurs"
    private let simple = "litteral.developper.simple-distributivite"
    private let signs = "nombres.relatifs.regle-des-signes"

    private func copy(_ student: String, _ exercise: String, _ result: SubmissionResult,
                      diagnosis: [StepDiagnosis?]? = nil, minutesAgo: Double = 0, attempt: Int = 1) -> Submission {
        Submission(
            studentID: student, exerciseID: exercise, assignmentID: "a", attemptNumber: attempt,
            correctionResult: CorrectionResult(stepResults: diagnosis?.map { $0 == nil } ?? [result.isSuccess],
                                               diagnosis: diagnosis),
            finalResult: result, timestamp: Date().addingTimeInterval(-minutesAgo * 60)
        )
    }

    private let exerciseSkills = [
        "e3": ["litteral.developper.trois-facteurs"],
        "e1": ["litteral.developper.simple-distributivite"],
    ]

    func testTaxonomyIsBundled() {
        XCTAssertGreaterThan(Taxonomy.shared.allSkills.count, 150)
        XCTAssertEqual(Taxonomy.shared.skill(threeFactors)?.competency.fr, "Développer")
        XCTAssertEqual(Taxonomy.shared.skill(threeFactors)?.domain.fr, "Calcul littéral")
        XCTAssertFalse(Taxonomy.shared.search("trois facteurs").isEmpty)
    }

    func testRightCopyIsASuccessForTheExerciseSkills() {
        let records = SkillDiagnosis.build(submissions: [copy("zoe", "e1", .success1st)], exerciseSkills: exerciseSkills)
        XCTAssertEqual(records["zoe"]?[simple]?.successes, 1)
    }

    func testWrongCopyCountsAgainstTheDiagnosedSkillOnly() {
        let wrong = copy("zoe", "e3", .failed, diagnosis: [
            nil,
            StepDiagnosis(skillID: signs, errorType: "sign_error"),
            StepDiagnosis(skillID: nil, errorType: "consequence"),
        ])
        let records = SkillDiagnosis.build(submissions: [wrong], exerciseSkills: exerciseSkills)
        XCTAssertEqual(records["zoe"]?[signs]?.failures, 1)
        XCTAssertEqual(records["zoe"]?[signs]?.mistakes.first?.errorType, "sign_error")
        XCTAssertNil(records["zoe"]?[threeFactors], "the exercise skill was not the one that failed")
    }

    func testWithoutDiagnosisTheExerciseSkillsFail() {
        let records = SkillDiagnosis.build(submissions: [copy("zoe", "e3", .failed)], exerciseSkills: exerciseSkills)
        XCTAssertEqual(records["zoe"]?[threeFactors]?.failures, 1)
    }

    func testMasteryAndTheTeacherSentence() {
        let failure = StepDiagnosis(skillID: threeFactors, errorType: "algebra")
        let copies = [
            copy("zoe", "e3", .failed, diagnosis: [failure], minutesAgo: 30),
            copy("zoe", "e3", .failed, diagnosis: [failure], minutesAgo: 20),
            copy("zoe", "e3", .success2nd, minutesAgo: 10, attempt: 2),
            copy("zoe", "e1", .success1st, minutesAgo: 5),
            copy("zoe", "e1", .success1st, minutesAgo: 4),
            copy("zoe", "e1", .success1st, minutesAgo: 3),
        ]
        let zoe = SkillDiagnosis.build(submissions: copies, exerciseSkills: exerciseSkills)["zoe"]!
        XCTAssertEqual(zoe[threeFactors]?.mastery, .notMastered)
        XCTAssertEqual(zoe[simple]?.mastery, .mastered)
        XCTAssertEqual(SkillDiagnosis.weakSkills(zoe).map(\.skillID), [threeFactors])
        let sentence = SkillDiagnosis.sentence(firstName: "Zoé", record: zoe[threeFactors]!)
        XCTAssertTrue(sentence.hasPrefix("En Développer, Zoé ne maîtrise pas : produit de trois facteurs"), sentence)
        XCTAssertTrue(sentence.contains("(1/3 réussis)"), sentence)
        XCTAssertFalse(sentence.contains("Erreur type"), "no free text about the student")
    }

    /// One slip fixed at the second try is not a gap; two failures are.
    func testVerdictNeedsEnoughCopies() {
        let slip = StepDiagnosis(skillID: simple, errorType: "algebra")
        let once = SkillDiagnosis.build(submissions: [
            copy("zoe", "e1", .failed, diagnosis: [slip]), copy("zoe", "e1", .success2nd, attempt: 2),
        ], exerciseSkills: exerciseSkills)["zoe"]!
        XCTAssertEqual(once[simple]?.mastery, .toConfirm)
        XCTAssertEqual(SkillDiagnosis.toWatch(once).map(\.skillID), [simple])
        let twice = SkillDiagnosis.build(submissions: [
            copy("zoe", "e1", .failed, diagnosis: [slip]), copy("zoe", "e1", .failed, diagnosis: [slip]),
        ], exerciseSkills: exerciseSkills)["zoe"]!
        XCTAssertEqual(twice[simple]?.mastery, .notMastered)
    }

    func testClassViewNamesTheStrugglingStudents() {
        let failure = StepDiagnosis(skillID: threeFactors, errorType: "algebra")
        let copies = [
            copy("zoe", "e3", .failed, diagnosis: [failure]), copy("zoe", "e3", .failed, diagnosis: [failure]),
            copy("noa", "e3", .success1st), copy("noa", "e3", .success1st),
        ]
        let perStudent = SkillDiagnosis.build(submissions: copies, exerciseSkills: exerciseSkills)
        let skill = SkillDiagnosis.classSkills(perStudent).first { $0.skillID == threeFactors }!
        XCTAssertEqual(skill.notMastered, ["zoe"])
        XCTAssertEqual(skill.students, 2)
        XCTAssertEqual(skill.rate, 0.5, accuracy: 0.001)
    }
}
