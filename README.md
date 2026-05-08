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

- **Students** log in with a class code (format `MX-XXXX`) or by scanning a QR code shown by the teacher. The session is persisted in the iPad Keychain. There is no individual student account in Firebase Auth.
- **Teachers** sign in with email + password (Firebase Auth). The auth layer is wrapped behind `AuthenticationService` to make adding SSO/magic-link/paid-tier login a contained refactor.

## Languages

The app is bilingual French/English. Teachers pick a language in their profile (Settings → Language); the choice persists and the entire UI updates immediately, no app restart required.

## Statistics

Five priority statistics are computed by `StatisticsService`:

1. AI-derived error taxonomy (per-step categories surfaced by the correction Cloud Function).
2. Per-concept mastery as a class-wide heatmap (success rate per competency).
3. Common error patterns (pairwise X→Y co-occurrence across the class).
4. Comparison to class average (per student).
5. Per-concept progress over time (12-week trend).

Reports are viewable in-app and exportable to PDF (per-student and per-exercise views) via the Statistics tab.

## Demo data

The teacher profile has a "Load demo data" button that seeds a sample class, students, groups, and exercises. "Reset Demo" wipes only the demo namespace; teacher-created data is untouched.

## Cloud Functions (Python)

Three callable functions in `functions/main.py`:

1. **`extract_exercise`** — Claude Vision reads an exercise photo → LaTeX statement + expected answer + suggested competency tags from the teacher's catalog.
2. **`recognize_handwriting`** — Claude Vision reads a PencilKit PNG export → list of LaTeX steps + confidence score.
3. **`correct_submission`** — Hybrid: Claude structures student steps vs. reference, SymPy verifies algebraic equivalence (Claude judgment fallback). Returns per-step booleans, first error index, optional notation note (when the class is in strict notation mode), and per-step error tags.

## Tests

- Cloud Functions: `pytest functions/tests`.
- iOS / macOS: build & test from Xcode (`Product → Test`).

## Project layout

```
├── Core/               models, services, repositories
├── Features/           ViewModels
├── UI/                 iOS & macOS views
├── MathClass-Shared/   shared SwiftUI components
├── MathClass/          iOS app entry point
├── MathClass-macOS/    macOS app entry point
└── functions/          Python Firebase Cloud Functions
```
