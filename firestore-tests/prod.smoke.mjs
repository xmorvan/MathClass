// Smoke test against the REAL Firebase project (no emulators).
// Creates a throwaway teacher, class and student, runs the student flow up
// to the drawing upload and submission, calls the AI functions once, then
// deletes everything through delete_account.
//
// Run: cd firestore-tests && node --test prod.smoke.mjs
// Reads the Firebase config from ../GoogleService-Info.plist.
// AI steps are reported, not asserted, so a missing Vertex AI quota shows up
// as a clear message instead of failing the whole run.

import { after, test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";

import { deleteApp, initializeApp } from "firebase/app";
import { createUserWithEmailAndPassword, getAuth, signInAnonymously } from "firebase/auth";
import {
  collection, doc, getDocs, initializeFirestore, query, serverTimestamp, setDoc, where,
} from "firebase/firestore";
import { getFunctions, httpsCallable } from "firebase/functions";
import { getBytes, getStorage, ref, uploadBytes } from "firebase/storage";

const plist = (key) => execFileSync(
  "/usr/libexec/PlistBuddy", ["-c", `Print :${key}`, "../GoogleService-Info.plist"],
).toString().trim();

const config = {
  apiKey: plist("API_KEY"),
  projectId: plist("PROJECT_ID"),
  storageBucket: plist("STORAGE_BUCKET"),
  appId: plist("GOOGLE_APP_ID"),
};

const PNG = Uint8Array.from(Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
  "base64",
));

const apps = [];
function device(name) {
  const app = initializeApp(config, name);
  apps.push(app);
  const functions = getFunctions(app, "europe-west6");
  return {
    auth: getAuth(app),
    db: initializeFirestore(app, { experimentalForceLongPolling: true }),
    storage: getStorage(app),
    call: (fn, data) => httpsCallable(functions, fn)(data).then((r) => r.data),
  };
}

const teacher = device("teacher");
const student = device("student");
const s = {};

after(async () => {
  // Clean up whatever was created, even after a failure.
  try { if (teacher.auth.currentUser) await teacher.call("delete_account"); } catch (e) { console.log("cleanup teacher:", e.message); }
  try { if (student.auth.currentUser) await student.auth.currentUser.delete(); } catch (e) { console.log("cleanup student:", e.message); }
  await Promise.all(apps.map((a) => deleteApp(a)));
});

test("teacher signs up, gets a class code, creates class/student/exercise", async () => {
  const email = `smoke-${Date.now()}@mathclass.test`;
  const cred = await createUserWithEmailAndPassword(teacher.auth, email, "Smoke1234");
  s.teacherID = cred.user.uid;
  await setDoc(doc(teacher.db, "users", s.teacherID), {
    email, firstName: "Smoke", lastName: "Test", role: "teacher", createdAt: serverTimestamp(),
  }, { merge: true });
  s.classCode = (await teacher.call("generate_class_code")).classCode;
  s.classID = `smoke-class-${Date.now()}`;
  await setDoc(doc(teacher.db, "classes", s.classID), {
    name: "Smoke", classCode: s.classCode, teacherID: s.teacherID, notationStrict: false,
  });
  s.studentID = "smoke-student";
  await setDoc(doc(teacher.db, "classes", s.classID, "students", s.studentID), {
    firstName: "Test", lastName: "Élève", classID: s.classID, level: 3,
  });
  s.exerciseID = `smoke-ex-${Date.now()}`;
  await setDoc(doc(teacher.db, "exercises", s.exerciseID), {
    statement: "Résoudre $2x = 8$", expectedAnswer: "x = 4", teacherID: s.teacherID,
  });
});

test("student joins, claims a seat, uploads a drawing and submits", async () => {
  await signInAnonymously(student.auth);
  const joined = await student.call("join_class", { classCode: s.classCode });
  assert.equal(joined.classID, s.classID);
  await student.call("claim_student_seat", { classCode: s.classCode, studentID: s.studentID });
  await student.auth.currentUser.getIdTokenResult(true);
  s.pngPath = `submissions/${s.classID}/${s.studentID}/${s.exerciseID}_attempt1.png`;
  await uploadBytes(ref(student.storage, s.pngPath), PNG, { contentType: "image/png" });
  const sub = doc(collection(student.db, "submissions"));
  await setDoc(sub, {
    studentID: s.studentID, classID: s.classID, teacherID: s.teacherID,
    exerciseID: s.exerciseID, latexSteps: ["2x = 8", "x = 4"], pngURL: s.pngPath,
    attemptNumber: 1, submittedAt: serverTimestamp(),
  });
  s.submissionID = sub.id;
});

test("AI functions (reported, not asserted)", async () => {
  try {
    const r = await student.call("recognize_handwriting", { storagePath: s.pngPath, format: "png" });
    console.log("recognize_handwriting OK:", JSON.stringify(r));
  } catch (e) {
    console.log("recognize_handwriting FAILED:", e.code, e.message);
  }
  try {
    const r = await student.call("correct_submission", {
      submissionID: s.submissionID, studentSteps: ["2x = 8", "x = 4"], attemptNumber: 1,
    });
    console.log("correct_submission OK:", JSON.stringify(r));
  } catch (e) {
    console.log("correct_submission FAILED:", e.code, e.message);
  }
});

test("teacher sees the submission and the drawing", async () => {
  const inbox = await getDocs(query(collection(teacher.db, "submissions"), where("teacherID", "==", s.teacherID)));
  assert.ok(inbox.docs.some((d) => d.id === s.submissionID));
  const bytes = await getBytes(ref(teacher.storage, s.pngPath));
  assert.equal(bytes.byteLength, PNG.byteLength);
});
