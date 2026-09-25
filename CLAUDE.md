# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

- **iOS / macOS:** Open `MathClass.xcodeproj` in Xcode, select target, `Cmd+R`
- **Firebase functions:** `firebase deploy --only functions,firestore:indexes`
- **Firebase emulator:** `firebase emulators:start`
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
- `StudentSessionManager` — student sessions stored in iOS Keychain (no Firebase Auth for students)
- `CorrectionService` / `ExerciseExtractionService` — HTTP clients for Cloud Functions
- `KaTeXRenderer` — converts LaTeX strings to HTML for display

**`Core/Repositories/`** — thin CRUD wrappers over FirebaseService, one per model type

**`Features/ViewModels/`** — `@Published` properties, call services/repos, never import SwiftUI

**`UI/iOS/Views/`** and **`UI/macOS/Views/`** — platform-specific views; share logic via ViewModels and `MathClass-Shared/`

### Student Authentication
Students have **no Firebase Auth account**. They log in via QR code or class code + name; session (studentID + classID) is persisted in the iOS Keychain. Test student UUID: `00000000-0000-0000-0000-000000000001`.

### Cloud Functions (Python)
Five functions in `functions/main.py`:
1. **`extract_exercise`** — Claude Vision reads an exercise photo → returns LaTeX statement + expected answer + AI-suggested `competencyIDs` chosen from the teacher's catalog (request includes `competencies: [{id,label}]`). Requires teacher auth + storagePath under `exercises/`.
2. **`recognize_handwriting`** — Claude Vision reads a PencilKit PNG export → returns list of LaTeX steps + confidence score. Requires student auth claim + storagePath under `submissions/{caller_studentID}/`.
3. **`correct_submission`** — Hybrid: Claude structures student steps vs. reference, SymPy verifies algebraic equivalence (fallback to Claude judgment), returns per-step boolean array, first error index, optional `notationNoteKey` (one of `missing_brackets`, `decimal_separator`, `implicit_multiplication`, `missing_unit`, `ambiguous_fraction`, `power_notation`) when the class has `notationStrict=true`, and per-step `errorTags` (e.g. "sign_error", "arithmetic", "notation"). The request includes `notationStrict: Bool`. Owner-checks the submission against `req.auth.token.studentID` before persisting via Admin SDK.
4. **`link_student_session`** — Bind an iPad student's anonymous Firebase Auth UID to a `(classID, studentID)` pair via custom claims. TOFU device-token check on first call; rejects subsequent device-mismatches. Required so subsequent Firestore / Storage / callable requests carry `request.auth.token.studentID` for the security rules and server-side ownership checks.
5. **`delete_student_data`** — Teacher-only GDPR right-to-erasure. Hard-deletes the student doc, all `/submissions/{id}` where `studentID == target`, all Storage objects under `submissions/{studentID}/`, and the student's `levelProgress/*` subtree. Verifies `classes/{classID}.teacherID == auth.uid` before any delete.

`notationNoteKey` localization: the Cloud Function returns a language-neutral key. The iOS client maps it to a localized phrase via `NotationNote.localizedMessage(forKey:)` in `Core/Models/Submission.swift`, which then runs through `Localizations.swift` for FR/EN.

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
/submissions/{submissionID}                              (correctionResult.notationNote, errorTags)
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
