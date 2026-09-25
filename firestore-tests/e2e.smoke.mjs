// End-to-end smoke test: the whole teacher → student → correction → teacher
// round trip, against the Auth, Firestore, Storage and Functions emulators,
// through the real client SDK (same calls as the app, no rules bypass).
//
// Claude is replaced by canned answers (CLAUDE_PROVIDER=fake, emulator
// only), so no API key or Vertex AI access is needed.
//
// Run: cd firestore-tests && npm install && npm run e2e
// (needs Java and the Python venv in functions/venv.)

import { after, before, test } from "node:test";
import assert from "node:assert/strict";

import { deleteApp, initializeApp } from "firebase/app";
import {
  connectAuthEmulator, createUserWithEmailAndPassword, getAuth, signInAnonymously,
} from "firebase/auth";
import {
  collection, connectFirestoreEmulator, doc, getDoc, getDocs, initializeFirestore,
  query, serverTimestamp, setDoc, where,
} from "firebase/firestore";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";
import { connectStorageEmulator, getBytes, getStorage, ref, uploadBytes } from "firebase/storage";

const PROJECT = "demo-mathclass";
const HOST = "127.0.0.1";
const config = {
  apiKey: "fake-api-key",
  projectId: PROJECT,
  storageBucket: `${PROJECT}.appspot.com`,
};

// A 1×1 PNG: enough for upload, the fake Claude ignores the pixels.
const PNG = Uint8Array.from(Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
  "base64",
));

const apps = [];

/** A separate app instance per user, like two different devices. */
function device(name) {
  const app = initializeApp(config, name);
  apps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, `http://${HOST}:9099`, { disableWarnings: true });
  const db = initializeFirestore(app, { experimentalForceLongPolling: true });
  connectFirestoreEmulator(db, HOST, 8080);
  const storage = getStorage(app);
  connectStorageEmulator(storage, HOST, 9199);
  const functions = getFunctions(app, "europe-west6");
  connectFunctionsEmulator(functions, HOST, 5001);
  const call = (fn, data) => httpsCallable(functions, fn)(data).then((r) => r.data);
  return { app, auth, db, storage, call };
}

after(async () => {
  await Promise.all(apps.map((a) => deleteApp(a)));
});

const state = {};

before(async () => {
  state.teacher = device("teacher");
  state.student = device("student");
});

test("teacher signs up and gets a profile", async () => {
  const { auth, db } = state.teacher;
  const email = `prof-${Date.now()}@mathclass.test`;
  const cred = await createUserWithEmailAndPassword(auth, email, "Demo1234");
  state.teacherID = cred.user.uid;
  // Same write as AuthenticationService.createAccount (setData merge).
  await setDoc(doc(db, "users", state.teacherID), {
    email, firstName: "Prof", lastName: "Démo", role: "teacher", createdAt: serverTimestamp(),
  }, { merge: true });
  const profile = await getDoc(doc(db, "users", state.teacherID));
  assert.equal(profile.data().role, "teacher");
});

test("teacher creates a class with a server-generated code", async () => {
  const { db, call } = state.teacher;
  const { classCode } = await call("generate_class_code");
  assert.match(classCode, /^MX-[A-Z0-9]{4}$/);
  state.classCode = classCode;
  state.classID = `class-${Date.now()}`;
  await setDoc(doc(db, "classes", state.classID), {
    name: "3e A", classCode, teacherID: state.teacherID, notationStrict: false,
  });
  state.studentID = "stu-alice";
  await setDoc(doc(db, "classes", state.classID, "students", state.studentID), {
    firstName: "Alice", lastName: "Martin", classID: state.classID, level: 3,
  });
  state.exerciseID = `ex-${Date.now()}`;
  await setDoc(doc(db, "exercises", state.exerciseID), {
    statement: "Résoudre $2x = 8$", expectedAnswer: "x = 4", teacherID: state.teacherID,
  });
  const roster = await getDocs(collection(db, "classes", state.classID, "students"));
  assert.equal(roster.size, 1);
});

test("student joins with the class code and claims a seat", async () => {
  const { auth, call } = state.student;
  await signInAnonymously(auth);
  const joined = await call("join_class", { classCode: state.classCode });
  assert.equal(joined.classID, state.classID);
  assert.deepEqual(joined.students.map((s) => `${s.firstName} ${s.lastInitial}`), ["Alice M."]);

  await call("claim_student_seat", { classCode: state.classCode, studentID: state.studentID });
  const token = await auth.currentUser.getIdTokenResult(true);
  assert.equal(token.claims.role, "student");
  assert.equal(token.claims.studentID, state.studentID);
});

test("student uploads a drawing (image content type required)", async () => {
  const { storage } = state.student;
  state.pngPath = `submissions/${state.classID}/${state.studentID}/${state.exerciseID}_attempt1.png`;
  // Without a content type the rules must refuse it (the old app bug).
  await assert.rejects(uploadBytes(ref(storage, `${state.pngPath}.raw`), PNG));
  await uploadBytes(ref(storage, state.pngPath), PNG, { contentType: "image/png" });
});

test("recognition reads the student's own drawing", async () => {
  const result = await state.student.call("recognize_handwriting", {
    storagePath: state.pngPath, format: "png",
  });
  assert.ok(result.steps.length > 0);
  state.steps = result.steps;
});

test("student submits and gets a graded result", async () => {
  const { db, call } = state.student;
  const submissionRef = doc(collection(db, "submissions"));
  await setDoc(submissionRef, {
    studentID: state.studentID, classID: state.classID, teacherID: state.teacherID,
    exerciseID: state.exerciseID, latexSteps: state.steps, pngURL: state.pngPath,
    attemptNumber: 1, submittedAt: serverTimestamp(),
  });
  state.submissionID = submissionRef.id;
  const graded = await call("correct_submission", {
    submissionID: state.submissionID, studentSteps: state.steps,
    expectedAnswer: "ignored by the server", statement: "ignored", attemptNumber: 1,
    notationStrict: false,
  });
  assert.equal(graded.stepResults.length, state.steps.length);
});

test("teacher sees the graded submission and the drawing", async () => {
  const { db, storage } = state.teacher;
  const inbox = await getDocs(query(
    collection(db, "submissions"),
    where("teacherID", "==", state.teacherID),
  ));
  const submission = inbox.docs.find((d) => d.id === state.submissionID);
  assert.ok(submission, "submission missing from teacher inbox");
  assert.ok(submission.data().finalResult, "submission was not graded");
  const bytes = await getBytes(ref(storage, state.pngPath));
  assert.equal(bytes.byteLength, PNG.byteLength);
});
