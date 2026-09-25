//
//  DemoSeedService.swift
//  MathClass
//
//  Idempotent demo content writer. Uses deterministic Firestore document
//  IDs so it can be re-run safely (writes are upserts) and "Reset Demo"
//  can target only the demo namespace without touching teacher-created
//  data. Designed for the salesperson scenario: open the app cold,
//  populate sample classes/students/exercises/submissions, walk a
//  prospect through the full teacher↔student loop.
//

import Foundation
import FirebaseFirestore

@MainActor
final class DemoSeedService {

    static let shared = DemoSeedService()

    private let firebase = FirebaseService.shared

    /// Fixed identifiers — all demo writes land at known paths so we can
    /// scope deletion / reset.
    enum DemoIDs {
        static let classID = "demo-class-3eA"
        static let teacherID = "demo-teacher"
        static let testStudentID = "00000000-0000-0000-0000-000000000001"
        static let chapterID = "demo-chapter-algebra"
        static let competency1 = "demo-comp-eq-1deg"
        static let competency2 = "demo-comp-eq-2deg"
        static let exercisePrefix = "demo-ex-"
        static let groupAID = "demo-group-a"
        static let groupBID = "demo-group-b"
    }

    private init() {}

    /// Run the seeder. Safe to call multiple times — every write is an
    /// idempotent upsert keyed off `DemoIDs`.
    func seed(teacherID: String) async throws {
        try await seedClass(teacherID: teacherID)
        try await seedChapterAndCompetencies()
        try await seedStudents()
        try await seedGroups()
        try await seedExercises(teacherID: teacherID)
    }

    /// Reset: delete only documents under demo IDs. Teacher-created classes
    /// and students remain untouched.
    func reset() async throws {
        // Students under the demo class
        let studentsPath = "classes/\(DemoIDs.classID)/students"
        let students: [Student] = (try? await firebase.getDocuments(from: studentsPath)) ?? []
        for s in students {
            if let id = s.id {
                try? await firebase.deleteDocument(from: studentsPath, documentID: id)
            }
        }
        // Groups
        let groupsPath = "classes/\(DemoIDs.classID)/groups"
        let groups: [StudentGroup] = (try? await firebase.getDocuments(from: groupsPath)) ?? []
        for g in groups {
            if let id = g.id {
                try? await firebase.deleteDocument(from: groupsPath, documentID: id)
            }
        }
        // Chapter + competencies
        let chaptersPath = "classes/\(DemoIDs.classID)/chapters"
        try? await firebase.deleteDocument(from: chaptersPath, documentID: DemoIDs.chapterID)
        // Demo exercises (only those with our prefix)
        let exercises: [Exercise] = (try? await firebase.getDocuments(from: "exercises")) ?? []
        for e in exercises where (e.id ?? "").hasPrefix(DemoIDs.exercisePrefix) {
            if let id = e.id {
                try? await firebase.deleteDocument(from: "exercises", documentID: id)
            }
        }
        // The class itself last so subcollections vanish in order.
        try? await firebase.deleteDocument(from: "classes", documentID: DemoIDs.classID)
    }

    // MARK: - Seeders

    private func seedClass(teacherID: String) async throws {
        let cls = ClassRoom(
            id: DemoIDs.classID,
            name: "Démo — 3ème A",
            classCode: "MX-DEMO",
            teacherID: teacherID,
            createdAt: Date(),
            notationStrict: true
        )
        _ = try await firebase.createDocument(cls, in: "classes", documentID: DemoIDs.classID)
    }

    private func seedChapterAndCompetencies() async throws {
        let chapter = Chapter(
            id: DemoIDs.chapterID,
            name: "Algèbre — équations",
            order: 0,
            classID: DemoIDs.classID
        )
        _ = try await firebase.createDocument(
            chapter,
            in: "classes/\(DemoIDs.classID)/chapters",
            documentID: DemoIDs.chapterID
        )

        let comp1 = Competency(
            id: DemoIDs.competency1,
            label: "Équations du 1er degré",
            chapterID: DemoIDs.chapterID
        )
        let comp2 = Competency(
            id: DemoIDs.competency2,
            label: "Équations du 2nd degré",
            chapterID: DemoIDs.chapterID
        )
        _ = try await firebase.createDocument(
            comp1,
            in: "classes/\(DemoIDs.classID)/chapters/\(DemoIDs.chapterID)/competencies",
            documentID: DemoIDs.competency1
        )
        _ = try await firebase.createDocument(
            comp2,
            in: "classes/\(DemoIDs.classID)/chapters/\(DemoIDs.chapterID)/competencies",
            documentID: DemoIDs.competency2
        )
    }

    private func seedStudents() async throws {
        // 20 demo students: spread across levels 1–5 (4 per level), with the
        // first slot mapped to the documented test-student UUID. Sized so the
        // post-seed dashboard and statistics views look populated rather
        // than starved for data.
        let students: [Student] = [
            Student(id: DemoIDs.testStudentID, firstName: "Alice", lastName: "Démo", classID: DemoIDs.classID, level: 4),
            Student(id: "demo-stu-2", firstName: "Bilel", lastName: "Aouad", classID: DemoIDs.classID, level: 3),
            Student(id: "demo-stu-3", firstName: "Camille", lastName: "Berger", classID: DemoIDs.classID, level: 2),
            Student(id: "demo-stu-4", firstName: "Daniel", lastName: "Costa", classID: DemoIDs.classID, level: 5),
            Student(id: "demo-stu-5", firstName: "Emma", lastName: "Diallo", classID: DemoIDs.classID, level: 1),
            Student(id: "demo-stu-6", firstName: "Farid", lastName: "El Amrani", classID: DemoIDs.classID, level: 3),
            Student(id: "demo-stu-7", firstName: "Gloria", lastName: "Fernandes", classID: DemoIDs.classID, level: 4),
            Student(id: "demo-stu-8", firstName: "Hugo", lastName: "Garcia", classID: DemoIDs.classID, level: 2),
            Student(id: "demo-stu-9", firstName: "Inès", lastName: "Hamida", classID: DemoIDs.classID, level: 3),
            Student(id: "demo-stu-10", firstName: "Jules", lastName: "Iverson", classID: DemoIDs.classID, level: 5),
            Student(id: "demo-stu-11", firstName: "Kenza", lastName: "Joubert", classID: DemoIDs.classID, level: 1),
            Student(id: "demo-stu-12", firstName: "Léo", lastName: "Kerouac", classID: DemoIDs.classID, level: 4),
            Student(id: "demo-stu-13", firstName: "Maya", lastName: "Lambert", classID: DemoIDs.classID, level: 2),
            Student(id: "demo-stu-14", firstName: "Noah", lastName: "Martins", classID: DemoIDs.classID, level: 3),
            Student(id: "demo-stu-15", firstName: "Olivia", lastName: "Nguyen", classID: DemoIDs.classID, level: 5),
            Student(id: "demo-stu-16", firstName: "Paul", lastName: "Olivier", classID: DemoIDs.classID, level: 1),
            Student(id: "demo-stu-17", firstName: "Quentin", lastName: "Petit", classID: DemoIDs.classID, level: 2),
            Student(id: "demo-stu-18", firstName: "Rania", lastName: "Quirin", classID: DemoIDs.classID, level: 4),
            Student(id: "demo-stu-19", firstName: "Sam", lastName: "Roussel", classID: DemoIDs.classID, level: 1),
            Student(id: "demo-stu-20", firstName: "Théa", lastName: "Sanchez", classID: DemoIDs.classID, level: 5)
        ]
        for s in students {
            guard let id = s.id else { continue }
            _ = try await firebase.createDocument(
                s,
                in: "classes/\(DemoIDs.classID)/students",
                documentID: id
            )
        }
    }

    private func seedGroups() async throws {
        let groupA = StudentGroup(
            id: DemoIDs.groupAID,
            name: "Renforcement",
            classID: DemoIDs.classID,
            studentIDs: ["demo-stu-3", "demo-stu-5", "demo-stu-8"]
        )
        let groupB = StudentGroup(
            id: DemoIDs.groupBID,
            name: "Avancés",
            classID: DemoIDs.classID,
            studentIDs: ["demo-stu-4", "demo-stu-10"]
        )
        _ = try await firebase.createDocument(
            groupA,
            in: "classes/\(DemoIDs.classID)/groups",
            documentID: DemoIDs.groupAID
        )
        _ = try await firebase.createDocument(
            groupB,
            in: "classes/\(DemoIDs.classID)/groups",
            documentID: DemoIDs.groupBID
        )
    }

    private func seedExercises(teacherID: String) async throws {
        struct Seed { let title: String; let statement: String; let answer: String; let level: Int; let comp: String }
        // 30 demo exercises: balanced across levels 1–5 and the two
        // demo competencies (linear vs quadratic equations).
        let seeds: [Seed] = [
            // Linear equations — competency1
            .init(title: "Résoudre 2x = 8", statement: "Résoudre $2x = 8$", answer: "x = 4", level: 1, comp: DemoIDs.competency1),
            .init(title: "Résoudre x + 5 = 12", statement: "Résoudre $x + 5 = 12$", answer: "x = 7", level: 1, comp: DemoIDs.competency1),
            .init(title: "Résoudre 4x = 20", statement: "Résoudre $4x = 20$", answer: "x = 5", level: 1, comp: DemoIDs.competency1),
            .init(title: "Résoudre 3x + 1 = 10", statement: "Résoudre $3x + 1 = 10$", answer: "x = 3", level: 2, comp: DemoIDs.competency1),
            .init(title: "Résoudre 2x - 4 = 6", statement: "Résoudre $2x - 4 = 6$", answer: "x = 5", level: 2, comp: DemoIDs.competency1),
            .init(title: "Résoudre 5x + 2 = 17", statement: "Résoudre $5x + 2 = 17$", answer: "x = 3", level: 2, comp: DemoIDs.competency1),
            .init(title: "Résoudre 5x - 7 = 2x + 8", statement: "Résoudre $5x - 7 = 2x + 8$", answer: "x = 5", level: 3, comp: DemoIDs.competency1),
            .init(title: "Résoudre 7x - 3 = 4x + 9", statement: "Résoudre $7x - 3 = 4x + 9$", answer: "x = 4", level: 3, comp: DemoIDs.competency1),
            .init(title: "Résoudre 2(x + 3) = 14", statement: "Résoudre $2(x + 3) = 14$", answer: "x = 4", level: 3, comp: DemoIDs.competency1),
            .init(title: "Résoudre 3(2x - 1) = 4x + 5", statement: "Résoudre $3(2x - 1) = 4x + 5$", answer: "x = 4", level: 4, comp: DemoIDs.competency1),
            .init(title: "Résoudre (x+2)/3 = (x-1)/2", statement: "Résoudre $\\frac{x+2}{3} = \\frac{x-1}{2}$", answer: "x = 7", level: 4, comp: DemoIDs.competency1),
            .init(title: "Résoudre 4(x-2) - 3(x+1) = 1", statement: "Résoudre $4(x-2) - 3(x+1) = 1$", answer: "x = 12", level: 4, comp: DemoIDs.competency1),
            .init(title: "Résoudre (3x+5)/4 - (x-2)/3 = 2", statement: "Résoudre $\\frac{3x+5}{4} - \\frac{x-2}{3} = 2$", answer: "x = 1", level: 5, comp: DemoIDs.competency1),
            .init(title: "Résoudre 2(3x - 4) - 5(x - 1) = 3x - 7", statement: "Résoudre $2(3x - 4) - 5(x - 1) = 3x - 7$", answer: "x = 2", level: 5, comp: DemoIDs.competency1),
            .init(title: "Résoudre x/2 + x/3 + x/6 = 6", statement: "Résoudre $\\frac{x}{2} + \\frac{x}{3} + \\frac{x}{6} = 6$", answer: "x = 6", level: 5, comp: DemoIDs.competency1),
            // Quadratic equations — competency2
            .init(title: "Résoudre x² = 9", statement: "Résoudre $x^2 = 9$", answer: "x = 3 \\text{ ou } x = -3", level: 1, comp: DemoIDs.competency2),
            .init(title: "Résoudre x² = 16", statement: "Résoudre $x^2 = 16$", answer: "x = 4 \\text{ ou } x = -4", level: 1, comp: DemoIDs.competency2),
            .init(title: "Résoudre x² - 1 = 0", statement: "Résoudre $x^2 - 1 = 0$", answer: "x = 1 \\text{ ou } x = -1", level: 2, comp: DemoIDs.competency2),
            .init(title: "Résoudre x² - 4 = 0", statement: "Résoudre $x^2 - 4 = 0$", answer: "x = 2 \\text{ ou } x = -2", level: 2, comp: DemoIDs.competency2),
            .init(title: "Résoudre x² - 9 = 0", statement: "Résoudre $x^2 - 9 = 0$", answer: "x = 3 \\text{ ou } x = -3", level: 2, comp: DemoIDs.competency2),
            .init(title: "Résoudre x² - 5x + 6 = 0", statement: "Résoudre $x^2 - 5x + 6 = 0$", answer: "x = 2 \\text{ ou } x = 3", level: 3, comp: DemoIDs.competency2),
            .init(title: "Résoudre x² + 3x - 4 = 0", statement: "Résoudre $x^2 + 3x - 4 = 0$", answer: "x = 1 \\text{ ou } x = -4", level: 3, comp: DemoIDs.competency2),
            .init(title: "Résoudre x² - 2x - 8 = 0", statement: "Résoudre $x^2 - 2x - 8 = 0$", answer: "x = 4 \\text{ ou } x = -2", level: 3, comp: DemoIDs.competency2),
            .init(title: "Résoudre x² + x - 6 = 0", statement: "Résoudre $x^2 + x - 6 = 0$", answer: "x = 2 \\text{ ou } x = -3", level: 4, comp: DemoIDs.competency2),
            .init(title: "Résoudre x² - 7x + 12 = 0", statement: "Résoudre $x^2 - 7x + 12 = 0$", answer: "x = 3 \\text{ ou } x = 4", level: 4, comp: DemoIDs.competency2),
            .init(title: "Résoudre x² + 5x + 6 = 0", statement: "Résoudre $x^2 + 5x + 6 = 0$", answer: "x = -2 \\text{ ou } x = -3", level: 4, comp: DemoIDs.competency2),
            .init(title: "Résoudre 2x² - 5x + 2 = 0", statement: "Résoudre $2x^2 - 5x + 2 = 0$", answer: "x = 2 \\text{ ou } x = 0.5", level: 5, comp: DemoIDs.competency2),
            .init(title: "Résoudre 3x² + 5x - 2 = 0", statement: "Résoudre $3x^2 + 5x - 2 = 0$", answer: "x = -2 \\text{ ou } x = 1/3", level: 5, comp: DemoIDs.competency2),
            .init(title: "Résoudre 2x² - 7x + 3 = 0", statement: "Résoudre $2x^2 - 7x + 3 = 0$", answer: "x = 3 \\text{ ou } x = 0.5", level: 5, comp: DemoIDs.competency2),
            .init(title: "Résoudre 4x² - 4x + 1 = 0", statement: "Résoudre $4x^2 - 4x + 1 = 0$", answer: "x = 0.5", level: 5, comp: DemoIDs.competency2)
        ]
        for (i, seed) in seeds.enumerated() {
            let id = "\(DemoIDs.exercisePrefix)\(i + 1)"
            let exercise = Exercise(
                id: id,
                title: seed.title,
                statement: seed.statement,
                statementImageURL: nil,
                expectedAnswer: seed.answer,
                chapterID: DemoIDs.chapterID,
                competencyIDs: [seed.comp],
                difficultyLevel: seed.level,
                creationMethod: .wysiwyg,
                teacherID: teacherID
            )
            _ = try await firebase.createDocument(
                exercise,
                in: "exercises",
                documentID: id
            )
        }
    }
}
