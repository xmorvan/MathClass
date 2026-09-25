//
//  DemoSeedService.swift
//  MathClass
//
//  Demo content for a prospect's trial: one class with students, groups,
//  six exercises and an active assignment, so a student iPad can join
//  with the class code and start solving right away.
//
//  Every demo document is scoped to the teacher (IDs derived from their
//  uid, a class code of its own), so any number of prospects can load
//  the demo side by side. Writes are upserts: seeding twice is safe.
//  "Reset" deletes only that teacher's demo class (server-side cascade)
//  and demo exercises.
//

import Foundation
import FirebaseFirestore

@MainActor
final class DemoSeedService {

    static let shared = DemoSeedService()

    private let firebase = FirebaseService.shared

    /// Identifiers of one teacher's demo documents. Paths under the demo
    /// class (students, groups, chapter) are already unique per class and
    /// keep fixed IDs.
    struct DemoIDs {
        let teacherID: String

        var classID: String { "demo-class-\(teacherID)" }
        var assignmentID: String { "demo-asg-\(teacherID)" }
        var exercisePrefix: String { "demo-ex-\(teacherID)-" }

        static let testStudentID = "00000000-0000-0000-0000-000000000001"
        static let chapterID = "demo-chapter-algebra"
        static let competency1 = "demo-comp-eq-1deg"
        static let competency2 = "demo-comp-eq-2deg"
        static let groupAID = "demo-group-a"
        static let groupBID = "demo-group-b"
        /// Demo exercises seeded in the teacher's library.
        static let exerciseCount = 30
        /// The first few go into the demo class's active assignment.
        static let assignmentExerciseCount = 6
    }

    private init() {}

    /// Run the seeder for `teacherID`. Safe to call multiple times.
    func seed(teacherID: String) async throws {
        let ids = DemoIDs(teacherID: teacherID)
        try await seedClass(ids)
        try await seedChapterAndCompetencies(ids)
        try await seedStudents(ids)
        try await seedGroups(ids)
        try await seedExercises(ids)
        try await seedAssignment(ids)
    }

    /// Delete this teacher's demo class (with its students' work) and demo
    /// exercises. Their own classes are untouched: a demo exercise that one
    /// of their assignments still uses is kept.
    func reset(teacherID: String) async throws {
        let ids = DemoIDs(teacherID: teacherID)
        let inUse = try await exerciseIDsUsedOutsideDemo(ids)
        let existing: ClassRoom? = try? await firebase.getDocument(ids.classID, from: "classes")
        if existing != nil {
            try await DataDeletionService.shared.deleteClass(id: ids.classID)
        }
        for index in 1...DemoIDs.exerciseCount {
            let exerciseID = "\(ids.exercisePrefix)\(index)"
            guard !inUse.contains(exerciseID) else { continue }
            try? await firebase.deleteDocument(from: "exercises", documentID: exerciseID)
        }
    }

    /// Exercise IDs referenced by assignments of the teacher's other classes.
    private func exerciseIDsUsedOutsideDemo(_ ids: DemoIDs) async throws -> Set<String> {
        let classes: [ClassRoom] = try await firebase.queryDocuments(
            from: "classes", whereField: "teacherID", isEqualTo: ids.teacherID
        )
        var used: Set<String> = []
        for classroom in classes where classroom.id != ids.classID {
            guard let classID = classroom.id else { continue }
            let assignments: [Assignment] = try await firebase.queryDocuments(
                from: "assignments", whereField: "classID", isEqualTo: classID
            )
            for assignment in assignments {
                guard let assignmentID = assignment.id else { continue }
                let exercises: [AssignmentExercise] = try await firebase.getDocuments(
                    from: "assignments/\(assignmentID)/exercises"
                )
                used.formUnion(exercises.map(\.exerciseID))
            }
        }
        return used
    }

    // MARK: - Seeders

    private func seedClass(_ ids: DemoIDs) async throws {
        // Keep the class code across re-seeds so students already joined
        // stay valid; otherwise ask the server for a fresh unique code.
        let existing: ClassRoom? = try? await firebase.getDocument(ids.classID, from: "classes")
        let classCode: String
        if let existingCode = existing?.classCode {
            classCode = existingCode
        } else {
            classCode = try await ClassCodeService.shared.generateUniqueCode()
        }
        let cls = ClassRoom(
            id: ids.classID,
            name: "Démo, 3e A",
            classCode: classCode,
            teacherID: ids.teacherID,
            createdAt: existing?.createdAt ?? Date(),
            notationStrict: true
        )
        _ = try await firebase.createDocument(cls, in: "classes", documentID: ids.classID)
    }

    private func seedChapterAndCompetencies(_ ids: DemoIDs) async throws {
        let chapter = Chapter(
            id: DemoIDs.chapterID,
            name: "Algèbre : équations",
            order: 0,
            classID: ids.classID
        )
        _ = try await firebase.createDocument(
            chapter,
            in: "classes/\(ids.classID)/chapters",
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
            in: "classes/\(ids.classID)/chapters/\(DemoIDs.chapterID)/competencies",
            documentID: DemoIDs.competency1
        )
        _ = try await firebase.createDocument(
            comp2,
            in: "classes/\(ids.classID)/chapters/\(DemoIDs.chapterID)/competencies",
            documentID: DemoIDs.competency2
        )
    }

    private func seedStudents(_ ids: DemoIDs) async throws {
        // 10 demo students: spread across levels 1–5, with a couple linked
        // and one that maps to the documented test-student UUID.
        let students: [Student] = [
            Student(id: DemoIDs.testStudentID, firstName: "Alice", lastName: "Démo", classID: ids.classID, level: 4),
            Student(id: "demo-stu-2", firstName: "Bilel", lastName: "Aouad", classID: ids.classID, level: 3),
            Student(id: "demo-stu-3", firstName: "Camille", lastName: "Berger", classID: ids.classID, level: 2),
            Student(id: "demo-stu-4", firstName: "Daniel", lastName: "Costa", classID: ids.classID, level: 5),
            Student(id: "demo-stu-5", firstName: "Emma", lastName: "Diallo", classID: ids.classID, level: 1),
            Student(id: "demo-stu-6", firstName: "Farid", lastName: "El Amrani", classID: ids.classID, level: 3),
            Student(id: "demo-stu-7", firstName: "Gloria", lastName: "Fernandes", classID: ids.classID, level: 4),
            Student(id: "demo-stu-8", firstName: "Hugo", lastName: "Garcia", classID: ids.classID, level: 2),
            Student(id: "demo-stu-9", firstName: "Inès", lastName: "Hamida", classID: ids.classID, level: 3),
            Student(id: "demo-stu-10", firstName: "Jules", lastName: "Iverson", classID: ids.classID, level: 5)
        ]
        for s in students {
            guard let id = s.id else { continue }
            _ = try await firebase.createDocument(
                s,
                in: "classes/\(ids.classID)/students",
                documentID: id
            )
        }
    }

    private func seedGroups(_ ids: DemoIDs) async throws {
        let groupA = StudentGroup(
            id: DemoIDs.groupAID,
            name: "Renforcement",
            classID: ids.classID,
            studentIDs: ["demo-stu-3", "demo-stu-5", "demo-stu-8"]
        )
        let groupB = StudentGroup(
            id: DemoIDs.groupBID,
            name: "Avancés",
            classID: ids.classID,
            studentIDs: ["demo-stu-4", "demo-stu-10"]
        )
        _ = try await firebase.createDocument(
            groupA,
            in: "classes/\(ids.classID)/groups",
            documentID: DemoIDs.groupAID
        )
        _ = try await firebase.createDocument(
            groupB,
            in: "classes/\(ids.classID)/groups",
            documentID: DemoIDs.groupBID
        )
    }

    private func seedExercises(_ ids: DemoIDs) async throws {
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
            let id = "\(ids.exercisePrefix)\(i + 1)"
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
                teacherID: ids.teacherID
            )
            _ = try await firebase.createDocument(
                exercise,
                in: "exercises",
                documentID: id
            )
        }
    }

    /// An active assignment with all demo exercises, so a student who joins
    /// with the class code has something to solve immediately.
    private func seedAssignment(_ ids: DemoIDs) async throws {
        let assignment = Assignment(
            id: ids.assignmentID,
            classID: ids.classID,
            mode: .differentiation,
            isActive: true
        )
        _ = try await firebase.createDocument(assignment, in: "assignments", documentID: ids.assignmentID)
        for index in 1...DemoIDs.assignmentExerciseCount {
            let exerciseID = "\(ids.exercisePrefix)\(index)"
            let assignmentExercise = AssignmentExercise(
                id: exerciseID,
                assignmentID: ids.assignmentID,
                exerciseID: exerciseID,
                order: index - 1
            )
            _ = try await firebase.createDocument(
                assignmentExercise,
                in: "assignments/\(ids.assignmentID)/exercises",
                documentID: exerciseID
            )
        }
    }
}
