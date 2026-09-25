# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

- **iOS / macOS:** Open `MathClass.xcodeproj` in Xcode, select target, `Cmd+R`
- **Firebase functions:** `firebase deploy --only functions,firestore:indexes`
- **Firebase emulator:** `firebase emulators:start`
- **Security-rules tests:** `cd firestore-tests && npm install && npm test` (emulators, needs Java)
- **Functions tests:** `cd functions && python -m pytest tests`
- Requires `GoogleService-Info.plist` in the project root (not in source control)
- Anthropic API key is stored as a Firebase secret. Before first deploy: `firebase functions:secrets:set ANTHROPIC_API_KEY`

## Architecture

### Tech Stack
- **Frontend:** SwiftUI (iOS 16+, macOS 12+), MVVM, ObservableObject ViewModels
- **Backend:** Firebase Firestore + Cloud Storage + Auth
- **Cloud Functions:** Python 3.12 in `europe-west6`, using Claude Haiku 4.5 + SymPy
- **Math rendering:** KaTeX via WKWebView bridge

### Project Structure
```
├── Core/               ← models, services, repositories
├── Features/           ← ViewModels
├── UI/                 ← iOS & macOS views
├── MathClass-Shared/   ← shared SwiftUI components
├── MathClass/          ← iOS app entry point
├── MathClass-macOS/    ← macOS app entry point
└── functions/          ← Python Firebase Cloud Functions
```

### Core Modules

**`Core/Services/`** — singleton services injected throughout the app:
- `FirebaseService` — all Firestore reads/writes go through here (never access `db` directly)
- `StudentSessionManager` — student login (anonymous Firebase Auth + `claim_student_seat` claims), session also kept in the iOS Keychain
- `CorrectionService` / `ExerciseExtractionService` — HTTP clients for Cloud Functions
- `KaTeXRenderer` — converts LaTeX strings to HTML for display

**`Core/Repositories/`** — thin CRUD wrappers over FirebaseService, one per model type

**`Features/ViewModels/`** — `@Published` properties, call services/repos, never import SwiftUI

**`UI/iOS/Views/`** and **`UI/macOS/Views/`** — platform-specific views; share logic via ViewModels and `MathClass-Shared/`

### Student Authentication
Students have no email account. They log in via QR code or class code + name: the iPad signs in with an **anonymous Firebase Auth** account, `join_class` returns the name picker list (first name + last-name initial), and `claim_student_seat` sets the custom claims `{role: "student", classID, studentID}` on that account. The session (studentID + classID + class code) is also persisted in the iOS Keychain. Test student UUID: `00000000-0000-0000-0000-000000000001`.

### Security rules
`firestore.rules` / `storage.rules` are ownership-based: a teacher reaches only classes whose `teacherID` is theirs; a student reaches only their own class and their own work (via the claims above). Consequences for code:
- Every `submissions` query must filter on `teacherID == uid` (teacher) or `studentID == <own id>` (student) — go through `SubmissionRepository.scopedQuery`. New submissions carry `classID` and `teacherID`.
- Never listen to a whole top-level collection (`periods`, `assignments`, `classes`); filter on `classID`/`teacherID`.
- Handwriting images live at `submissions/{classID}/{studentID}/…` in Storage.
- Class-code lookups are server-side (`join_class`, `generate_class_code`).
- Cover rule changes in `firestore-tests/rules.test.mjs`.

### Cloud Functions (Python)
Functions in `functions/main.py` (every one checks the caller via `functions/auth_guard.py`):
1. **`extract_exercise`** — Claude Vision reads an exercise photo → returns LaTeX statement + expected answer + AI-suggested `competencyIDs` chosen from the teacher's catalog (request includes `competencies: [{id,label}]`).
2. **`recognize_handwriting`** — Claude Vision reads a PencilKit PNG export → returns list of LaTeX steps + confidence score.
3. **`correct_submission`** — Hybrid: Claude structures student steps vs. reference, SymPy verifies algebraic equivalence (fallback to Claude judgment), returns per-step boolean array, first error index, optional `notationNoteKey` (localized client-side via `NotationNote.localizedMessage(forKey:)`) when the class has `notationStrict=true`, and per-step `errorTags` (e.g. "sign_error", "arithmetic", "notation"). The caller must own the submission; the expected answer, statement and `notationStrict` are read from Firestore, not taken from the request.
4. **`join_class`** / **`claim_student_seat`** — student class-code login (see Student Authentication).
5. **`generate_class_code`** — unique `MX-XXXX` code for a new class (teachers only).
6. **`delete_student_data`** — teacher-only GDPR right-to-erasure: hard-deletes the student doc, their `/submissions`, Storage objects under `submissions/{studentID}/` and `levelProgress/*`, after checking `classes/{classID}.teacherID == auth.uid`.

### Localization
The app is bilingual French/English. FR is the source-of-truth for keys: views call `Text("Foo")` with the French copy as the literal, and `String.tr` looks up the English translation in `Core/Resources/Localizations.swift`. The teacher profile has a language picker; the choice is persisted in `UserDefaults` and the SwiftUI tree rebuilds via `.id(language)` so every visible string flips immediately. `LocalizationManager.shared` is the single source of truth.

### Data Flow (student solving an exercise)
Student draws → PencilKit PNG exported → `recognize_handwriting` → student verifies LaTeX → `correct_submission` → per-step feedback in `FeedbackView`

### Firestore Structure
```
/classes/{classID}                                       (notationStrict, ...)
/classes/{classID}/students/{studentID}                  (level: 1–5, groupID?)
/classes/{classID}/groups/{groupID}                      (named subset of students)
/classes/{classID}/chapters/{chapterID}/competencies/{competencyID}
/exercises/{exerciseID}
/assignments/{assignmentID}/exercises/{assignmentExerciseID}   (legacy, parallel to sessions)
/periods/{periodID}                                      (one class hour)
/periods/{periodID}/sessions/{sessionID}                 (ordered slot, mode A/B/C, allowFreeOrder)
/periods/{periodID}/sessions/{sessionID}/exercises/{ae}  (per-student/per-group exercise list)
/submissions/{submissionID}                              (studentID, classID, teacherID, correctionResult.notationNote, errorTags)
```

The Period+Session schema is the new home for assignments. The legacy
flat `/assignments/{...}` collection still exists in code for
transitional callers and is kept compatible.

## Code Conventions
- **Imports:** Group by framework (SwiftUI → Foundation → Firebase*)
- **Naming:** camelCase for variables, PascalCase for types
- **Comments:** `MARK:` for section separation, `///` for complex functions
- **Error handling:** `do-catch` for async operations
- **Conditionals:** `guard` for early returns, `if-let` for optional unwrapping
- **Types:** Prefer explicit types over inference when declaring properties
- **Extensions:** Place in `Extensions.swift` unless type-specific
- **Firebase access:** Always via `FirebaseService`, never direct `db` calls
- **SwiftUI:** Use `ViewBuilder` for conditional view construction
