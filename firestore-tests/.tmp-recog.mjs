import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { initializeApp } from "firebase/app";
import { getAuth, signInAnonymously } from "firebase/auth";
import { getFunctions, httpsCallable } from "firebase/functions";
const p = (k) => execFileSync("/usr/libexec/PlistBuddy", ["-c", `Print :${k}`, "../GoogleService-Info.plist"]).toString().trim();
const app = initializeApp({ apiKey: p("API_KEY"), projectId: p("PROJECT_ID"), storageBucket: p("STORAGE_BUCKET"), appId: p("GOOGLE_APP_ID") });
const auth = getAuth(app); const fns = getFunctions(app, "europe-west6");
const call = (n, d) => httpsCallable(fns, n)(d).then((r) => r.data);
await signInAnonymously(auth);
const j = await call("join_class", { classCode: "MX-XMW8" });
const noe = j.students.find((s) => s.firstName === "Noé");
await call("claim_student_seat", { classCode: "MX-XMW8", studentID: noe.id });
await auth.currentUser.getIdTokenResult(true);
try {
  const r = await call("recognize_handwriting", { imageBase64: readFileSync(".tmp-lea.png").toString("base64"), format: "png" });
  console.log("OK", JSON.stringify(r));
} catch (e) { console.log("ERR", e.code, "|", e.message, "|", JSON.stringify(e.details)); }
await auth.currentUser.delete();
process.exit(0);
