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
Three functions in `functions/main.py`:
1. **`extract_exercise`** — Claude Vision reads an exercise photo → returns LaTeX statement + expected answer
2. **`recognize_handwriting`** — Claude Vision reads a PencilKit PNG export → returns list of LaTeX steps + confidence score
3. **`correct_submission`** — Hybrid: Claude structures student steps vs. reference, SymPy verifies algebraic equivalence (fallback to Claude judgment), returns per-step boolean array + first error index

### Data Flow (student solving an exercise)
Student draws → PencilKit PNG exported → `recognize_handwriting` → student verifies LaTeX → `correct_submission` → per-step feedback in `FeedbackView`

### Firestore Structure
```
/classes/{classID}/students/{studentID}
/exercises/{exerciseID}
/assignments/{assignmentID}/exercises/{assignmentExerciseID}
/submissions/{submissionID}
```

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
