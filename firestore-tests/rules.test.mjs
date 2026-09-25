// Security-rules tests for firestore.rules and storage.rules.
//
// Each test mirrors a read or write the app really makes (see the
// repositories in Core/Repositories/), plus the attacks the rules must stop.
//
// Run: cd firestore-tests && npm install && npm test
// (starts the Firestore + Storage emulators; needs Java.)

import { after, before, beforeEach, describe, test } from "node:test";
import { readFileSync } from "node:fs";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  addDoc, collection, deleteDoc, doc, getDoc, getDocs, limit, orderBy,
  query, setDoc, updateDoc, where,
} from "firebase/firestore";
import { getBytes, ref, uploadBytes } from "firebase/storage";

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-mathclass",
    firestore: { rules: readFileSync("../firestore.rules", "utf8"), host: "127.0.0.1", port: 8080 },
    storage: { rules: readFileSync("../storage.rules", "utf8"), host: "127.0.0.1", port: 9199 },
  });
});

after(async () => {
  await env?.cleanup();
});

// ── Identities ───────────────────────────────────────

const teacher = () => env.authenticatedContext("teacher-1", {
  firebase: { sign_in_provider: "password" },
});
const otherTeacher = () => env.authenticatedContext("teacher-2", {
  firebase: { sign_in_provider: "password" },
});
// Signed up but never wrote a teacher profile.
const noProfile = () => env.authenticatedContext("nobody", {
  firebase: { sign_in_provider: "password" },
});
const student = (studentID = "stu-1", classID = "class-1") =>
  env.authenticatedContext(`anon-${studentID}`, {
    firebase: { sign_in_provider: "anonymous" },
    role: "student",
    classID,
    studentID,
  });
// Anonymous account that has not claimed a seat yet.
const anonymous = () => env.authenticatedContext("anon-fresh", {
  firebase: { sign_in_provider: "anonymous" },
});
const nobody = () => env.unauthenticatedContext();

// ── Fixture data ─────────────────────────────────────

const SUBMISSION = {
  studentID: "stu-1",
  classID: "class-1",
  teacherID: "teacher-1",
  exerciseID: "ex-1",
  assignmentID: "asg-1",
  attemptNumber: 1,
  latexSteps: ["2x = 8", "x = 4"],
  timeSpent: 30,
  timestamp: new Date("2026-09-01T10:00:00Z"),
};

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const docs = {
      "users/teacher-1": { role: "teacher", email: "t1@example.com" },
      "users/teacher-2": { role: "teacher", email: "t2@example.com" },
      "classes/class-1": { name: "3ème A", classCode: "MX-AB23", teacherID: "teacher-1" },
      "classes/class-1/students/stu-1": { firstName: "Camille", lastName: "Berger" },
      "classes/class-1/students/stu-2": { firstName: "Alice", lastName: "Démo" },
      "classes/class-1/students/stu-1/levelProgress/asg-1": { currentLevel: 2 },
      "classes/class-1/groups/g-1": { name: "Avancés", studentIDs: ["stu-1"] },
      "classes/class-1/chapters/ch-1": { name: "Équations" },
      "classes/class-1/chapters/ch-1/competencies/c-1": { label: "1er degré" },
      "classes/class-1b": { name: "3ème C", classCode: "MX-CD45", teacherID: "teacher-1" },
      "classes/class-2": { name: "4ème B", classCode: "MX-ZZ99", teacherID: "teacher-2" },
      "classes/class-2/students/stu-9": { firstName: "Zoé", lastName: "Martin" },
      "exercises/ex-1": { title: "2x = 8", teacherID: "teacher-1", chapterID: "ch-1" },
      "assignments/asg-1": { classID: "class-1", isActive: true },
      "assignments/asg-1/exercises/ae-1": { exerciseID: "ex-1", order: 0 },
      "assignments/asg-2": { classID: "class-2", isActive: true },
      "periods/p-1": { classID: "class-1", name: "Lundi 10h" },
      "periods/p-1/sessions/s-1": { periodID: "p-1", order: 0 },
      "periods/p-1/sessions/s-1/exercises/ae-1": { exerciseID: "ex-1", order: 0 },
      "periods/p-2": { classID: "class-2", name: "Mardi 8h" },
      "submissions/sub-1": SUBMISSION,
      "submissions/sub-2": { ...SUBMISSION, studentID: "stu-2" },
      "submissions/sub-9": { ...SUBMISSION, studentID: "stu-9", classID: "class-2", teacherID: "teacher-2", assignmentID: "asg-2" },
    };
    for (const [path, data] of Object.entries(docs)) {
      await setDoc(doc(db, path), data);
    }
  });
});

// ── Firestore ────────────────────────────────────────

describe("strangers", () => {
  test("cannot read anything", async () => {
    const db = nobody().firestore();
    await assertFails(getDoc(doc(db, "classes/class-1")));
    await assertFails(getDocs(query(collection(db, "classes"), where("classCode", "==", "MX-AB23"))));
    await assertFails(getDocs(collection(db, "classes/class-1/students")));
    await assertFails(getDoc(doc(db, "submissions/sub-1")));
    await assertFails(getDoc(doc(db, "exercises/ex-1")));
    await assertFails(getDoc(doc(db, "classes/class-1/students/stu-1/levelProgress/asg-1")));
  });

  test("an anonymous account without a seat cannot read or submit", async () => {
    const db = anonymous().firestore();
    await assertFails(getDoc(doc(db, "classes/class-1")));
    await assertFails(getDocs(collection(db, "classes/class-1/students")));
    await assertFails(getDocs(query(collection(db, "classes"), where("classCode", "==", "MX-AB23"))));
    await assertFails(addDoc(collection(db, "submissions"), SUBMISSION));
  });

  test("cannot list all classes or all submissions", async () => {
    await assertFails(getDocs(collection(teacher().firestore(), "classes")));
    await assertFails(getDocs(collection(student().firestore(), "submissions")));
    await assertFails(getDocs(collection(teacher().firestore(), "submissions")));
  });
});

describe("users", () => {
  test("a teacher reads and edits only their own profile", async () => {
    const db = teacher().firestore();
    await assertSucceeds(getDoc(doc(db, "users/teacher-1")));
    await assertFails(getDoc(doc(db, "users/teacher-2")));
    await assertSucceeds(updateDoc(doc(db, "users/teacher-1"), { firstName: "Xavier" }));
    await assertFails(updateDoc(doc(db, "users/teacher-1"), { role: "admin" }));
  });

  test("sign-up creates a teacher profile; students cannot", async () => {
    await assertSucceeds(setDoc(doc(noProfile().firestore(), "users/nobody"), { role: "teacher" }));
    await assertFails(setDoc(doc(student().firestore(), "users/anon-stu-1"), { role: "teacher" }));
  });
});

describe("teacher", () => {
  test("lists their classes (ClassRepository.startListening)", async () => {
    const db = teacher().firestore();
    const snap = await assertSucceeds(getDocs(query(collection(db, "classes"), where("teacherID", "==", "teacher-1"))));
    if (snap.size !== 2) throw new Error(`expected 2 classes, got ${snap.size}`);
    await assertFails(getDocs(query(collection(db, "classes"), where("teacherID", "==", "teacher-2"))));
  });

  test("a signed-in user without a teacher profile gets nothing", async () => {
    const db = noProfile().firestore();
    await assertFails(getDocs(query(collection(db, "classes"), where("teacherID", "==", "nobody"))));
    await assertFails(getDoc(doc(db, "exercises/ex-1")));
    await assertFails(setDoc(doc(db, "classes/new"), { name: "x", classCode: "MX-NEW1", teacherID: "nobody" }));
  });

  test("manages their class, roster, groups and chapters", async () => {
    const db = teacher().firestore();
    await assertSucceeds(setDoc(doc(db, "classes/class-3"), { name: "5ème", classCode: "MX-NEW1", teacherID: "teacher-1" }));
    await assertFails(setDoc(doc(db, "classes/class-4"), { name: "5ème", classCode: "MX-NEW2", teacherID: "teacher-2" }));
    await assertSucceeds(updateDoc(doc(db, "classes/class-1"), { notationStrict: false }));
    await assertFails(updateDoc(doc(db, "classes/class-1"), { teacherID: "teacher-2" }));
    await assertSucceeds(getDocs(collection(db, "classes/class-1/students")));
    await assertSucceeds(addDoc(collection(db, "classes/class-1/students"), { firstName: "Hugo", lastName: "Garcia" }));
    await assertSucceeds(updateDoc(doc(db, "classes/class-1/students/stu-1"), { level: 3 }));
    await assertSucceeds(getDocs(collection(db, "classes/class-1/groups")));
    await assertSucceeds(getDocs(collection(db, "classes/class-1/chapters")));
    await assertSucceeds(getDocs(collection(db, "classes/class-1/chapters/ch-1/competencies")));
    await assertSucceeds(getDoc(doc(db, "classes/class-1/students/stu-1/levelProgress/asg-1")));
  });

  test("cannot touch another teacher's class", async () => {
    const db = otherTeacher().firestore();
    await assertFails(getDoc(doc(db, "classes/class-1")));
    await assertFails(getDocs(collection(db, "classes/class-1/students")));
    await assertFails(updateDoc(doc(db, "classes/class-1"), { name: "hacked" }));
    await assertFails(addDoc(collection(db, "classes/class-1/students"), { firstName: "x", lastName: "y" }));
    await assertFails(getDocs(collection(db, "classes/class-1/groups")));
    await assertFails(getDoc(doc(db, "classes/class-1/students/stu-1/levelProgress/asg-1")));
  });

  test("exercise library: reads any, edits only their own", async () => {
    const db = otherTeacher().firestore();
    await assertSucceeds(getDocs(query(collection(db, "exercises"), where("teacherID", "==", "teacher-2"))));
    await assertSucceeds(getDocs(query(collection(db, "exercises"), where("chapterID", "==", "ch-1"))));
    await assertFails(updateDoc(doc(db, "exercises/ex-1"), { title: "hacked" }));
    await assertFails(deleteDoc(doc(db, "exercises/ex-1")));
    await assertSucceeds(setDoc(doc(db, "exercises/ex-2"), { title: "x", teacherID: "teacher-2" }));
    await assertFails(setDoc(doc(db, "exercises/ex-3"), { title: "x", teacherID: "teacher-1" }));
    await assertFails(updateDoc(doc(teacher().firestore(), "exercises/ex-1"), { teacherID: "teacher-2" }));
  });

  test("assignments and periods of their classes, by classID and by `in`", async () => {
    const db = teacher().firestore();
    await assertSucceeds(getDocs(query(collection(db, "assignments"), where("classID", "==", "class-1"))));
    await assertSucceeds(getDocs(query(collection(db, "assignments"), where("classID", "in", ["class-1", "class-1b"]))));
    await assertFails(getDocs(query(collection(db, "assignments"), where("classID", "in", ["class-1", "class-2"]))));
    await assertSucceeds(getDocs(collection(db, "assignments/asg-1/exercises")));
    await assertSucceeds(setDoc(doc(db, "assignments/asg-3"), { classID: "class-1", isActive: false }));
    await assertFails(setDoc(doc(db, "assignments/asg-4"), { classID: "class-2", isActive: false }));
    await assertFails(updateDoc(doc(db, "assignments/asg-1"), { classID: "class-2" }));

    await assertSucceeds(getDocs(query(collection(db, "periods"), where("classID", "==", "class-1"))));
    await assertSucceeds(getDocs(query(collection(db, "periods"), where("classID", "in", ["class-1", "class-1b"]))));
    await assertFails(getDocs(collection(db, "periods")));
    await assertSucceeds(getDocs(collection(db, "periods/p-1/sessions")));
    await assertSucceeds(getDocs(collection(db, "periods/p-1/sessions/s-1/exercises")));
    await assertSucceeds(addDoc(collection(db, "periods/p-1/sessions"), { periodID: "p-1", order: 1 }));
    await assertFails(getDocs(collection(db, "periods/p-2/sessions")));
    await assertFails(addDoc(collection(db, "periods/p-2/sessions"), { periodID: "p-2", order: 1 }));
  });

  test("submissions: only their own classes', always filtered by teacherID", async () => {
    const db = teacher().firestore();
    // SubmissionRepository.startListeningForTeacher
    const inbox = await assertSucceeds(getDocs(query(
      collection(db, "submissions"),
      where("teacherID", "==", "teacher-1"),
      where("assignmentID", "in", ["asg-1", "asg-2"]),
      orderBy("timestamp", "desc"),
      limit(100),
    )));
    if (inbox.size !== 2) throw new Error(`expected 2 submissions, got ${inbox.size}`);
    await assertSucceeds(getDocs(query(collection(db, "submissions"), where("teacherID", "==", "teacher-1"), where("exerciseID", "==", "ex-1"))));
    await assertSucceeds(getDoc(doc(db, "submissions/sub-1")));
    // Without the teacherID filter the query is refused.
    await assertFails(getDocs(query(collection(db, "submissions"), where("assignmentID", "==", "asg-1"))));
    await assertFails(getDocs(query(collection(db, "submissions"), where("teacherID", "==", "teacher-2"))));
    await assertFails(getDoc(doc(db, "submissions/sub-9")));
  });

  test("cannot create submissions or move one to another teacher", async () => {
    const db = teacher().firestore();
    await assertFails(addDoc(collection(db, "submissions"), SUBMISSION));
    await assertSucceeds(updateDoc(doc(db, "submissions/sub-1"), { latexSteps: ["x = 4"] }));
    await assertFails(updateDoc(doc(db, "submissions/sub-1"), { teacherID: "teacher-2" }));
    await assertFails(updateDoc(doc(db, "submissions/sub-1"), { studentID: "stu-2" }));
    await assertFails(deleteDoc(doc(db, "submissions/sub-1")));
  });
});

describe("student", () => {
  test("reads their class, own student doc, groups and chapters", async () => {
    const db = student().firestore();
    await assertSucceeds(getDoc(doc(db, "classes/class-1")));
    await assertSucceeds(getDoc(doc(db, "classes/class-1/students/stu-1")));
    await assertSucceeds(getDocs(collection(db, "classes/class-1/groups")));
    await assertSucceeds(getDocs(collection(db, "classes/class-1/chapters")));
    await assertSucceeds(getDoc(doc(db, "exercises/ex-1")));
  });

  test("cannot read classmates or other classes", async () => {
    const db = student().firestore();
    await assertFails(getDoc(doc(db, "classes/class-1/students/stu-2")));
    await assertFails(getDocs(collection(db, "classes/class-1/students")));
    await assertFails(getDoc(doc(db, "classes/class-2")));
    await assertFails(getDocs(collection(db, "classes/class-2/groups")));
    await assertFails(getDocs(query(collection(db, "classes"), where("classCode", "==", "MX-ZZ99"))));
  });

  test("updates only the deviceToken of their own student doc", async () => {
    const db = student().firestore();
    await assertSucceeds(updateDoc(doc(db, "classes/class-1/students/stu-1"), { deviceToken: "ipad-1" }));
    await assertFails(updateDoc(doc(db, "classes/class-1/students/stu-1"), { level: 5 }));
    await assertFails(updateDoc(doc(db, "classes/class-1/students/stu-2"), { deviceToken: "ipad-1" }));
  });

  test("assignments and periods of their class only (StudentViewModel)", async () => {
    const db = student().firestore();
    await assertSucceeds(getDocs(query(collection(db, "assignments"), where("classID", "==", "class-1"))));
    await assertSucceeds(getDocs(collection(db, "assignments/asg-1/exercises")));
    await assertFails(getDocs(query(collection(db, "assignments"), where("classID", "==", "class-2"))));
    await assertFails(getDoc(doc(db, "assignments/asg-2")));
    await assertSucceeds(getDocs(query(collection(db, "periods"), where("classID", "==", "class-1"))));
    await assertSucceeds(getDocs(collection(db, "periods/p-1/sessions")));
    await assertSucceeds(getDocs(collection(db, "periods/p-1/sessions/s-1/exercises")));
    await assertFails(getDoc(doc(db, "periods/p-2")));
    await assertFails(addDoc(collection(db, "periods/p-1/sessions"), { periodID: "p-1", order: 9 }));
    await assertFails(updateDoc(doc(db, "assignments/asg-1"), { isActive: false }));
    await assertFails(setDoc(doc(db, "exercises/ex-1"), { title: "x", teacherID: "teacher-1" }));
  });

  test("level progress: own only", async () => {
    const db = student().firestore();
    await assertSucceeds(getDoc(doc(db, "classes/class-1/students/stu-1/levelProgress/asg-1")));
    await assertSucceeds(setDoc(doc(db, "classes/class-1/students/stu-1/levelProgress/asg-1"), { currentLevel: 3 }));
    await assertFails(setDoc(doc(db, "classes/class-1/students/stu-2/levelProgress/asg-1"), { currentLevel: 5 }));
    await assertFails(getDoc(doc(db, "classes/class-1/students/stu-2/levelProgress/asg-1")));
  });

  test("reads own submissions, filtered by studentID", async () => {
    const db = student().firestore();
    await assertSucceeds(getDocs(query(collection(db, "submissions"), where("studentID", "==", "stu-1"), where("assignmentID", "==", "asg-1"))));
    await assertSucceeds(getDocs(query(
      collection(db, "submissions"),
      where("studentID", "==", "stu-1"),
      where("exerciseID", "==", "ex-1"),
      where("assignmentID", "==", "asg-1"),
      where("attemptNumber", "==", 1),
    )));
    await assertSucceeds(getDoc(doc(db, "submissions/sub-1")));
    await assertFails(getDoc(doc(db, "submissions/sub-2")));
    await assertFails(getDocs(query(collection(db, "submissions"), where("studentID", "==", "stu-2"))));
    await assertFails(getDocs(query(collection(db, "submissions"), where("assignmentID", "==", "asg-1"))));
  });

  test("creates a submission only as themselves, without a grade", async () => {
    const db = student().firestore();
    await assertSucceeds(addDoc(collection(db, "submissions"), SUBMISSION));
    await assertFails(addDoc(collection(db, "submissions"), { ...SUBMISSION, studentID: "stu-2" }));
    await assertFails(addDoc(collection(db, "submissions"), { ...SUBMISSION, classID: "class-2" }));
    await assertFails(addDoc(collection(db, "submissions"), { ...SUBMISSION, teacherID: "teacher-2" }));
    await assertFails(addDoc(collection(db, "submissions"), { ...SUBMISSION, finalResult: "success_1st" }));
    await assertFails(addDoc(collection(db, "submissions"), {
      ...SUBMISSION,
      correctionResult: { stepResults: [true, true], firstErrorIndex: null },
    }));
  });

  test("cannot grade or edit a submission afterwards", async () => {
    const db = student().firestore();
    await assertFails(updateDoc(doc(db, "submissions/sub-1"), { finalResult: "success_1st" }));
    await assertFails(deleteDoc(doc(db, "submissions/sub-1")));
  });

  test("a forged claim for another class gets nothing from this class", async () => {
    const db = student("stu-9", "class-2").firestore();
    await assertFails(getDoc(doc(db, "classes/class-1")));
    await assertFails(getDoc(doc(db, "submissions/sub-1")));
    await assertSucceeds(getDoc(doc(db, "submissions/sub-9")));
  });
});

// ── Storage ──────────────────────────────────────────

describe("storage", () => {
  const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47]);
  const meta = { contentType: "image/png" };

  beforeEach(async () => {
    await env.clearStorage();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const storage = ctx.storage();
      await uploadBytes(ref(storage, "submissions/class-1/stu-1/ex-1_attempt1.png"), png, meta);
      await uploadBytes(ref(storage, "exercises/abc.jpg"), png, { contentType: "image/jpeg" });
    });
  });

  test("a student uploads and reads back only their own drawings", async () => {
    const storage = student().storage();
    await assertSucceeds(uploadBytes(ref(storage, "submissions/class-1/stu-1/ex-1_attempt2.png"), png, meta));
    await assertSucceeds(getBytes(ref(storage, "submissions/class-1/stu-1/ex-1_attempt1.png")));
    await assertFails(uploadBytes(ref(storage, "submissions/class-1/stu-2/ex-1_attempt1.png"), png, meta));
    await assertFails(getBytes(ref(student("stu-2").storage(), "submissions/class-1/stu-1/ex-1_attempt1.png")));
    await assertFails(uploadBytes(ref(storage, "submissions/class-1/stu-1/notes.txt"), png, { contentType: "text/plain" }));
  });

  test("the class's teacher reads drawings; other teachers and strangers do not", async () => {
    const path = "submissions/class-1/stu-1/ex-1_attempt1.png";
    await assertSucceeds(getBytes(ref(teacher().storage(), path)));
    await assertFails(getBytes(ref(otherTeacher().storage(), path)));
    await assertFails(getBytes(ref(nobody().storage(), path)));
    await assertFails(getBytes(ref(anonymous().storage(), path)));
    await assertFails(uploadBytes(ref(teacher().storage(), path), png, meta));
  });

  test("exercise images: teachers write, teachers and students read", async () => {
    await assertSucceeds(uploadBytes(ref(teacher().storage(), "exercises/new.jpg"), png, { contentType: "image/jpeg" }));
    await assertFails(uploadBytes(ref(student().storage(), "exercises/new2.jpg"), png, { contentType: "image/jpeg" }));
    await assertSucceeds(getBytes(ref(student().storage(), "exercises/abc.jpg")));
    await assertFails(getBytes(ref(nobody().storage(), "exercises/abc.jpg")));
  });
});
