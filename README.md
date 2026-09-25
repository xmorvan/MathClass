# MathClass

MathClass is an educational application that helps middle-school and high-school teachers run differentiated classroom sessions. Students solve handwritten math exercises on iPad with a stylus; an AI checks each step of their reasoning; the teacher sees real-time progress and rich post-session analytics.

## Platforms

- **Teacher app:** iPad and Mac (interchangeable).
- **Student app:** iPad only (stylus-driven; no Mac student client).
- **Backend:** Firebase Firestore + Cloud Storage + Auth.
- **AI:** Anthropic Claude (server-side only, via Python Cloud Functions).

## Build & Run

- Open `MathClass.xcodeproj` in Xcode, select target, `Cmd+R`.
- Cloud Functions: `firebase deploy --only functions,firestore:indexes` (Python 3.12, region `europe-west6`).
- Firebase emulator: `firebase emulators:start`.
- `GoogleService-Info.plist` must be present at the project root (not in source control).
- The Anthropic API key is a Firebase secret. First-time setup: `firebase functions:secrets:set ANTHROPIC_API_KEY`.

## Authentication

- **Students** log in with a class code (format `MX-XXXX`) or by scanning a QR code shown by the teacher, then pick their name. Behind the scenes the iPad signs in with an *anonymous* Firebase account, and the `claim_student_seat` Cloud Function binds it to that student (custom claims `role`, `classID`, `studentID`). The session is also kept in the iPad Keychain.
- **Teachers** sign in with email + password (Firebase Auth). The auth layer is wrapped behind `AuthenticationService` to make adding SSO/magic-link/paid-tier login a contained refactor.

## Data protection

`firestore.rules` and `storage.rules` enforce who sees what:

- A teacher reaches only the classes they own and everything under them (students, submissions, handwriting images).
- A student reaches only their own class's content and their own work. Classmates' records are not readable; the name picker shows first names and last-name initials, served by the `join_class` Cloud Function.
- Nobody else reads anything. Grades are written only by the `correct_submission` Cloud Function, which grades against the exercise stored in Firestore, not against values sent by the app.

Rules tests run against the Firebase emulators (needs Java): `cd firestore-tests && npm install && npm test`.

### Deploying the security changes

1. Firebase console → Authentication → Sign-in method: enable **Anonymous**.
2. `firebase deploy --only functions,firestore:rules,firestore:indexes,storage`. On the first deploy, accept the prompt that lets Storage rules read Firestore (cross-service rules).
3. Submissions written before this change have no `teacherID` and no longer show in the teacher's views; student sessions saved before it ask the student to enter the class code once more.

## Languages

The app is bilingual French/English. Teachers pick a language in their profile (Settings → Language); the choice persists and the entire UI updates immediately, no app restart required.

## Statistics

Five priority statistics are computed by `StatisticsService`:

1. AI-derived error taxonomy (per-step categories surfaced by the correction Cloud Function).
2. Per-concept mastery as a class-wide heatmap (success rate per competency).
3. Common error patterns (pairwise X→Y co-occurrence across the class).
4. Comparison to class average (per student).
5. Per-concept progress over time (12-week trend).

Reports are viewable in-app. PDF export is single-page in the MVP and rich-chart on macOS only; the iPad PDF currently emits a text summary without the charts. Multi-page parent-meeting reports are planned for v1.1.

## Demo data

The teacher profile has a "Load demo data" button that seeds a sample class, students, groups, and exercises. "Reset Demo" wipes only the demo namespace; teacher-created data is untouched.

## Cloud Functions (Python)

Callable functions in `functions/main.py`. Every one checks the caller (`functions/auth_guard.py`): teachers for `extract_exercise` and `generate_class_code`, the owning student for `recognize_handwriting` and `correct_submission`.

1. **`extract_exercise`** — Claude Vision reads an exercise photo → LaTeX statement + expected answer + suggested competency tags from the teacher's catalog.
2. **`recognize_handwriting`** — Claude Vision reads a PencilKit PNG export → list of LaTeX steps + confidence score.
3. **`correct_submission`** — Hybrid: Claude structures student steps vs. reference, SymPy verifies algebraic equivalence (Claude judgment fallback). Returns per-step booleans, first error index, optional notation note (when the class is in strict notation mode), and per-step error tags.
4. **`join_class`** / **`claim_student_seat`** — class-code login for students (see Authentication).
5. **`generate_class_code`** — a new class's unique `MX-XXXX` code.

## Tests

- Cloud Functions: `pytest functions/tests`.
- Security rules: `cd firestore-tests && npm install && npm test` (Firebase emulators, needs Java).
- iOS / macOS: build & test from Xcode (`Product → Test`).

## Project layout

```
├── Core/               models, services, repositories
├── Features/           ViewModels
├── UI/                 iOS & macOS views
├── MathClass-Shared/   shared SwiftUI components
├── MathClass/          iOS app entry point
├── MathClass-macOS/    macOS app entry point
├── functions/          Python Firebase Cloud Functions
├── firestore-tests/    security-rules tests (Firebase emulators)
├── website/            public site (landing page, privacy policy) for static hosting
└── docs/               legal/ (privacy, processor agreement, notes for counsel), lancement/ (TestFlight guide, App Store texts)
```
