# MathClass — MVP Action Plan

## Context

This plan exists because the codebase is roughly two-thirds of the way to a sellable demo and the founder needs a clear, scoped punch list to close the gap. The student-solving pipeline (PencilKit canvas → handwriting recognition → confirm/edit modal → hybrid SymPy+Claude correction → mode-aware feedback) already works end-to-end on iPad, including all three correction modes and level progression. The teacher app has class/student/exercise CRUD parity on iPad and Mac, plus a working submission inbox. What's missing is everything that turns "a student can solve an exercise" into "a teacher can run a differentiated class hour and walk away with insights": per-student levels, groups, sessions with timing, a live dashboard during the lesson, charts in the analytics views, PDF export, demo seed data, the QR scanner, English UI, and a notation-strictness path that distinguishes sloppy notation from wrong math. The intended outcome is a polished, reliable demo that ships with sample content and lets a salesperson walk into a school and run the full teacher↔student loop.

Founder's locked-in architectural decisions (asked during planning):
- **Concept tags** = use existing curated `Competency` records as the tag universe; AI picks from that catalog rather than emitting free-form strings.
- **Session model** = introduce new `Period` + `Session` Firestore entities; each Session can carry a per-student or per-group `AssignmentExercise` list.
- **QR scanner** = ship it on the iPad student onboarding (AVFoundation + camera permission).
- **Bilingual FR/EN in MVP** = ship both languages with a teacher-side language toggle (overrides original spec line "MVP is English-only; FR/EN toggle is v2"). Same string-extraction work as English-only; toggle UI adds ≈ 1 day; both fr.lproj and en.lproj are populated. See risk note in §6.
- **Library-edit flows are MVP** = `EditExerciseView.swift` (iPad) and `ExerciseEditorView_macOS.swift` are explicitly in scope. The spec's "no editing exercise after assigned" still applies (no snapshot logic exists, so it's automatic), but editing exercises in the library is a first-class teacher capability.

---

## 1. Codebase audit summary

The tech stack matches `CLAUDE.md` exactly: SwiftUI MVVM with `@StateObject`/`@Published` ViewModels, Firebase 11.7.0 via SPM (Auth + Firestore + Storage + Functions), Python 3.12 Cloud Functions in `europe-west6` calling Claude Haiku 4.5 (`claude-haiku-4-5-20251001`), KaTeX rendered through a `WKWebView` bridge, PencilKit on iPad. Firestore offline persistence is **enabled** with unlimited cache (`MathClassApp.swift:20–24`, `MathClass_macOSApp.swift:19`), so the spec'd "offline submission queue" is largely free out of the box and only needs verification. Three Cloud Functions are registered and used (`extract_exercise`, `recognize_handwriting`, `correct_submission`); `correct_submission` already does hybrid SymPy + Claude with first-error indexing and server-side persistence via Admin SDK. Tests cover `correct_submission` only; the other two functions have zero tests.

Notable deltas vs. CLAUDE.md and the spec: (a) the entire UI is hardcoded in **French** despite the MVP being English-only — `Core/Resources/{en,fr}.lproj` exist but are empty; (b) `README.md` describes a teacher-side QR PDF export that does not exist in code; (c) `CorrectionService` does not accept a `notationStrict` flag and `correct_submission.py` has no notation-aware path; (d) `Student` has no level field, no `Group` model exists, and `Assignment` is flat (no time bounds, no session structure); (e) the macOS submission inbox listens live but is a flat list, not a per-student grid.

Overall health is good: code organization respects the documented boundaries (`FirebaseService` is the single Firestore entry point, ViewModels avoid SwiftUI imports, platform splits are clean — iPad compiles teacher+student views, Mac is teacher-only with no `StudentView_macOS`). Biggest risks are the data-model expansions required for groups/sessions/levels, and the volume of UI surface that needs English copy and inline one-liner hints.

---

## 2. Things to BUILD or COMPLETE for the MVP

Status legend: **missing** | **partial** | **present-but-unverified** | **present-and-working** (verified by reading code).
Complexity: **S** ≤ ½ day · **M** 1–3 days · **L** 4–7 days · **XL** > 1 week. Single-developer estimates.

| # | Feature | Where it lives | What already exists | Status | Complexity | Depends on |
|---|---|---|---|---|---|---|
| 1 | Bilingual UI (FR + EN) — extract every hardcoded string into `Localizable.strings`; carry the existing copy into `fr.lproj/Localizable.strings` (FR is source-of-truth for keys); produce an EN translation in `en.lproj/Localizable.strings`; add a language picker in `TeacherProfileView` and `TeacherProfileView_macOS` that overrides `Bundle.preferredLocalizations` per session and persists the choice; QA every screen in both languages | every `.swift` view file in `UI/iOS/Views/`, `UI/macOS/Views/`, `MathClass-Shared/`, plus model `displayName` getters; new picker UI in both teacher profile views | French strings hardcoded; `en.lproj`/`fr.lproj` directories exist but empty; one model already uses `String(localized:)` (e.g. `AssignmentMode.displayName`) | missing | L | — |
| 2 | Per-student level 1–5 — add `level: Int` (1–5 clamped) to `Student`; edit UI on add/edit student forms on both platforms | `Core/Models/Student.swift`; `UI/iOS/Views/AddStudentView.swift`; `UI/macOS/Views/{AddStudentView_macOS,EditStudentView_macOS,ClassStudentsView_macOS}.swift` | `Exercise.difficultyLevel` is the analogous field on exercises; `LevelProgressRepository` tracks per-assignment progress (different concept — keep both) | missing | S | — |
| 3 | Group model + Group CRUD — new `Core/Models/Group.swift` (`id`, `classID`, `name`, `studentIDs`); `Core/Repositories/GroupRepository.swift`; drag-to-group UI on macOS class detail; add to Firestore rules | new files; `UI/macOS/Views/ClassDetailView_macOS.swift` extension; `firestore.rules` | `AssignmentExercise.targetGroupName: String?` is a label-only hint with no model; `targetStudentIDs: [String]?` already filters | missing | M | — |
| 4 | Group-aware exercise targeting — change `AssignmentExercise.targetGroupName` to `targetGroupID` (or add it alongside) and resolve via `GroupRepository` when fetching `getExercisesForStudent` | `Core/Models/AssignmentExercise.swift`; `Core/Repositories/AssignmentRepository.swift` (~lines 221–230) | targeting plumbing exists, only needs the group resolution step | partial | S | 3 |
| 5 | AI tag suggestion using existing competencies — extend `extract_exercise.py` to also return up to 5 `competencyIDs` chosen from the teacher's catalog; teacher accepts/removes/adds before save | `functions/extract_exercise.py`; `Core/Services/ExerciseExtractionService.swift` (`ExtractionResult`); `Features/ViewModels/ExerciseEditorViewModel.swift`; `UI/iOS/Views/AddExerciseView.swift`; `UI/macOS/Views/ExerciseEditor/ExerciseMetadataPanel_macOS.swift` | `Exercise.competencyIDs: [String]` already exists; `ChapterRepository` and Competency CRUD wired; image-import + extraction work end-to-end on both platforms | partial | M | — |
| 6 | Class-level notation strictness — `Classroom.notationStrict: Bool` (default `true`); UI toggle in class detail; pass through `CorrectionService.correctAndUpdate` → `correct_submission.py`; correction returns `{stepResults, firstErrorIndex, notationNote: String?}`; `FeedbackView` renders the note as a separate banner without flipping the verdict | `Core/Models/Classroom.swift`; `UI/macOS/Views/EditClassView_macOS.swift` + iOS equivalent; `Core/Services/CorrectionService.swift`; `functions/correct_submission.py`; `Core/Models/Submission.swift` (`CorrectionResult` adds `notationNote: String?`); `UI/iOS/Views/Student/FeedbackView.swift` | nothing on the class side; `FeedbackView` already renders per-step ticks/crosses + first-error highlight | missing | M | — |
| 7 | Period + Session entities — new `Core/Models/Period.swift` (`id`, `classID`, `startTime`, `endTime`, `name`); new `Core/Models/Session.swift` (`id`, `periodID`, `order`, `mode: AssignmentMode`, `allowFreeOrder: Bool`); per-session `AssignmentExercise` subcollection (move existing). Migrate `Assignment.swift` into `Session` (rename + struct shape) — keep an `Assignment` typealias if needed for transitional callers | new model files; `Core/Repositories/{PeriodRepository,SessionRepository}.swift`; `firestore.rules`; `firestore.indexes.json`; rename consumers in `AssignmentRepository`/`AssignmentViewModel`; data migration helper for existing demo/test docs | `Assignment` (`classID`, `mode`, `isActive`, `createdAt`) + `AssignmentExercise` already in place; mode A/B/C semantics already encoded in `AssignmentMode` | partial | L | — |
| 8 | Linear-vs-free order toggle — add `allowFreeOrder: Bool` to `Session` (default `false` = linear); UI checkbox in session creation; runtime: when free, `StudentView` exposes a list-of-cards instead of forcing the next exercise | `Core/Models/Session.swift` (after #7); `UI/macOS/Views/Assignment/CreateAssignmentView_macOS.swift` (rename + extend); `UI/iOS/Views/Assignment/AssignmentListView_iOS.swift`; `Features/ViewModels/StudentViewModel.swift` | `AssignmentExercise.order: Int` already orders exercises; `StudentViewModel.advanceToNextExercise` walks linearly | missing | S | 7 |
| 9 | iPad bulk student import — paste-from-Excel and CSV file picker on iOS, matching the macOS UX | `UI/iOS/Views/AddStudentView.swift` + new `UI/iOS/Views/AddClassView.swift` if separating; reuse `StudentImportParser` (already in `TeacherViewModel.swift:302–374`) | macOS `AddClassView_macOS` has paste TextEditor + CSV NSOpenPanel; parser is platform-agnostic | missing | S | — |
| 10 | QR scanner — AVFoundation `AVCaptureMetadataOutput` view; integrate into iPad onboarding flow; fallback to manual code | new `UI/iOS/Views/StudentOnboarding/QRScannerView.swift`; `Features/ViewModels/StudentOnboardingViewModel.swift`; `Info.plist` `NSCameraUsageDescription` (manual edit list) | `ClassCodeService.generateQRCode` (lines 71–97) and class-code typing path both work | missing | S | — |
| 11 | Teacher live dashboard (per-student grid) — new tab in macOS teacher app showing each student's tile (current exercise + working/done) for the active session of an active period; updates via Firestore listener on submissions + per-student current-exercise field | new `UI/macOS/Views/Live/LiveDashboardView_macOS.swift`; new `Features/ViewModels/LiveDashboardViewModel.swift`; reuse `SubmissionRepository.startListeningForTeacher` | macOS `SubmissionInboxView_macOS` is a flat live list — useful prior art for Firestore listeners | missing | M | 7 |
| 12 | iPad parity for the live dashboard — same view structure on iPad teacher mode | `UI/iOS/Views/Live/LiveDashboardView.swift` | — | missing | S | 11 |
| 13 | "Finished early — push more exercises" — when a student's `currentExerciseIndex` exceeds their list and the session is still active, mark the tile "Terminé"; teacher right-clicks/long-presses the tile to push extra exercises into the session | `LiveDashboardViewModel`; `SessionRepository.appendExercises(forStudent:)` | `StudentViewModel.advanceToNextExercise` already sets `currentExercise = nil` past the end | missing | S | 7, 11 |
| 14 | Charts framework — link Apple's `Charts` (iOS 16+ / macOS 13+) to both targets; baseline minimum deployment confirmed in `.pbxproj` (manual step for founder) | every statistics view that needs a chart | none — `Package.resolved` shows only Firebase | missing | S | — |
| 15 | Stat: error-pattern co-occurrence (X→Y) — pairwise frequency of student-step error categories within and across exercises | `Core/Services/StatisticsService.swift` (extend); `UI/macOS/Views/Statistics/ExerciseErrorAnalysisView.swift` (new co-occurrence chart) | per-step `commonErrors` (most-common wrong LaTeX) is already aggregated | partial | M | 14, 16 |
| 16 | Stat: AI-derived error taxonomy — `correct_submission.py` returns one short error category per failed step (e.g. "sign error", "computation", "notation"); persisted on `CorrectionResult` and aggregated by `StatisticsService` | `functions/correct_submission.py`; `Submission.swift` (`CorrectionResult.errorTags: [String?]`); `StatisticsService` | hybrid pipeline already structures pairs; adding a category field is incremental | missing | M | — |
| 17 | Stat: per-concept progress over time — time-bucketed success rate per `competencyID`, per student and class average | `Core/Services/StatisticsService.swift`; new `UI/macOS/Views/Statistics/ConceptTrendView.swift`; iPad parity | snapshot-only `competencyRates` exist | missing | M | 14 |
| 18 | Stat: comparison-to-class-average (in-app) — student's success rate vs class mean per concept; bar chart per concept | `UI/macOS/Views/Statistics/StudentStatsDetailView.swift`; `StatisticsView` on iPad | data already in `ClassStats` (`overallSuccessRate`, `weakestCompetencies`); only the viz is missing | partial | S | 14 |
| 19 | PDF export — per-student and per-exercise reports; render the same SwiftUI view through `ImageRenderer` to a multipage PDF | new `Core/Utils/PDFExporter.swift` (uses `ImageRenderer` + `UIGraphicsPDFRenderer` on iOS / `NSPrintOperation` on macOS); export buttons in both Statistics views | none — README mentions PDF generation that does not exist in code | missing | M | 14, 15, 17, 18 |
| 20 | Demo seed data — `Core/Services/DemoSeedService.swift` writes one sample class, ~20 students across 5 levels, ~30 exercises tagged across competencies, a few past sessions with submissions; idempotent (uses fixed UUIDs); honors test-student UUID `00000000-0000-0000-0000-000000000001` | new service; called from `TeacherProfileView` button | none — grep returns zero matches for "demo"/"seed"/"sample" | missing | M | 2, 3, 7 |
| 21 | "Reset Demo" button — wipes only the demo namespace (deterministic IDs) and re-runs the seeder; confirmation dialog | `UI/iOS/Views/TeacherProfileView.swift`; `UI/macOS/Views/TeacherProfileView_macOS.swift` | none | missing | S | 20 |
| 22 | Reusable `InlineHint` component — one-line caption styled component placed under each interactive control | new `MathClass-Shared/InlineHint.swift`; sweep across ~30 views to apply | sporadic ad-hoc captions exist (e.g. `VerificationView.swift:192`, `ExerciseErrorAnalysisView.swift:154`) | partial | M | — |
| 23 | Multi-line proof support audit — confirm `recognize_handwriting.py` output handles 5–10 step proofs end-to-end, that `FeedbackView` scrolls when the step list is long, and that `correct_submission.py`'s 30-step input cap (`tests/test_correct_submission.py:266`) is sufficient | `functions/recognize_handwriting.py`; `functions/correct_submission.py`; `UI/iOS/Views/Student/FeedbackView.swift` | step-by-step rendering present; cap is a tested guard | present-but-unverified | S | — |
| 24 | Offline submission flow verified end-to-end — confirm Firestore persistence + Storage upload queueing handle the airplane-mode → reconnect path; add an in-flight "Waiting for connection" badge in `VerificationView` so students aren't confused | `UI/iOS/Views/Student/VerificationView.swift`; `UI/iOS/Views/ExerciseView.swift` | `PersistentCacheSettings(sizeBytes: unlimited)` is set; Storage uploads are not auto-queued — needs a custom queue if upload starts offline | present-but-unverified | M | — |
| 25 | Tighten Firestore rules on submissions — currently `read: if true` (line 120 of `firestore.rules`); restrict to the submission's student via device-token check or to the teacher who owns the parent class | `firestore.rules` | comment in rules already flags this as a follow-up | partial | S | — |
| 26 | Teacher auth abstraction — wrap `AuthenticationService` behind an `AuthProvider` protocol so SSO/email-link/paid-tier can drop in later without rewriting call sites | `Core/Services/AuthenticationService.swift`; consumers (`TeacherSignUpViewModel`, `TeacherProfileViewModel`, root content views) | Firebase email/password works end-to-end | present-and-working | S | — |
| 27 | Cloud Function deploy runbook + smoke tests — verify `firebase deploy --only functions,firestore:indexes`, document the `ANTHROPIC_API_KEY` secret rotation, add `pytest` smoke tests for `extract_exercise.py` and `recognize_handwriting.py` mirroring `test_correct_submission.py` | `functions/tests/test_extract_exercise.py`; `functions/tests/test_recognize_handwriting.py`; `README.md` | only `correct_submission` has tests | partial | S | — |
| 28 | README and CLAUDE.md cleanup — remove the README claim that PDFs are generated already; sync the test-student UUID and seed naming once #20 ships | `README.md`; `CLAUDE.md` | both contain aspirational claims that are now incorrect | partial | S | 19, 20 |

**Total estimated effort**: roughly 35–45 dev-days for a single experienced Swift+Firebase developer.

---

## 3. Out-of-scope code (leave untouched)

| File / Module | What it does | Out-of-scope feature it relates to | Isolated or entangled |
|---|---|---|---|
| `Core/Models/Chapter.swift`, `Core/Repositories/ChapterRepository.swift`, `Core/Models/Competency.swift` | Curated chapter/competency catalog the teacher manages manually | The "no curated tag universe" interpretation of concept tags — the founder elected to keep this catalog as the tag universe, so it's MVP-relevant under the chosen interpretation, but the catalog-management UI is not actively being worked on | **Entangled** — `Exercise.competencyIDs`, `StatisticsService` competency rollups, and AI-suggested tags (#5) all key off this catalog. Treat these as MVP infrastructure, not deletable code |
| `Core/Resources/fr.lproj/` | Empty placeholder for French localization | French UI (v2) | Isolated — empty directory, no entries |
| `Features/ViewModels/StudentOnboardingViewModel.swift` (only the parts beyond class-code/name lookup) | Multi-step student onboarding UX | Teacher onboarding tutorial / first-launch walkthrough is out of scope; the student class-code+name flow itself **is** in MVP | Entangled — student class-code login is MVP; the file is mixed |
| `LevelProgressRepository.swift` and the per-assignment level progression in `AssignmentModeHandler.swift` | Per-assignment 3-in-a-row level progression | Not out-of-scope — this is mode B and is MVP. Listed only to be explicit it stays | n/a |

No code matching the explicitly out-of-scope features (Mac student client, theory delivery, AI-generated curriculum exercises, parent views, accessibility flags, "stuck" detection, French UI shipped, teacher tutorial, exercise-after-assigned editing) was found in the repo. Nothing to leave alone there.

---

## 4. Suggested implementation order

Each slice ships one user-visible capability end-to-end. Order is chosen so the demo tells a richer story after every slice.

1. **Slice 1 — Bilingual MVP (≈ 5–8 days)**
   What the founder can demo afterward: the app launches in the device locale; the teacher can flip a switch in their profile to FR or EN at any time and every screen, modal, and Cloud Function-derived label re-renders correctly. A salesperson can demo to a French school in French and an English school in English from the same build. Builds: #1.

2. **Slice 2 — Class & roster differentiation primitives (≈ 4–6 days)**
   Demo: teacher creates a class, paste-imports students from Excel on iPad, sets each student's level 1–5, and creates two named groups by dragging students. Builds: #2, #3, #4, #9.

3. **Slice 3 — Period + Session model with timing and free-order (≈ 4–6 days)**
   Demo: teacher schedules a Period 10:00–11:00 with two Sessions; Session 1 = "Algebra revision" linear order to Group A, "Geometry challenge" free order to Group B. Migrates `Assignment` → `Session`. Builds: #7, #8.

4. **Slice 4 — AI-suggested tags from competency catalog (≈ 1–3 days)**
   Demo: teacher imports an exercise photo; AI fills statement, expected answer, and proposes 3 tags from the teacher's catalog; teacher tweaks and saves. Builds: #5.

5. **Slice 5 — Notation strictness end-to-end (≈ 1–3 days)**
   Demo: teacher toggles strictness on the class; student submits "4+-1=3" → marked correct with a notation note rather than wrong. Builds: #6.

6. **Slice 6 — QR scanner + iPad onboarding polish (≈ ½ day)**
   Demo: student opens the iPad app, scans the printed QR card, taps their name, ready to work. Builds: #10. (Manual `Info.plist` step listed.)

7. **Slice 7 — Live teacher dashboard with "push more" (≈ 3–5 days)**
   Demo: teacher launches the planned Session; the dashboard fills with student tiles updating in real time; a fast student is flagged "Done" and the teacher pushes 2 extra exercises. Builds: #11, #12, #13.

8. **Slice 8 — Charts and the five priority statistics (≈ 5–8 days)**
   Demo: at the end of class, the teacher opens the per-student and per-exercise reports; concept-mastery heatmap, X→Y error co-occurrence, AI-classified error types, vs-class-average bars, and per-concept trend lines all render. Builds: #14, #15, #16, #17, #18.

9. **Slice 9 — PDF export (≈ 1–3 days)**
   Demo: teacher exports a parent-meeting report from the per-student view; same for an end-of-unit report from the per-exercise view. Builds: #19.

10. **Slice 10 — Demo seed + Reset Demo (≈ 2 days)**
    Demo: salesperson opens the app cold; class, students, exercises, and last-week's submissions are already populated. After a pitch, "Reset Demo" wipes back to clean state in one tap. Builds: #20, #21.

11. **Slice 11 — Reliability & polish (≈ 4–7 days)**
    Demo: full run-through with airplane-mode test; inline hints under every control; tightened security rules; smoke tests passing in CI. Builds: #22, #23, #24, #25, #26, #27, #28.

Order rationale: English first so every subsequent demo screenshot is sale-ready; data-model expansions (slices 2–3) gate everything else; AI tag suggestion and notation are quick polish wins on the existing exercise/correction flows; live dashboard requires Sessions to exist; statistics depth is the biggest "wow" lift and benefits from real submission data, which only the seeder provides at the end.

---

## 5. Open questions for the founder

Each is yes/no or multiple-choice. Phrased to be answerable in one line.

- **Mapping of the 5 stats to per-student vs per-exercise views** — proposed: (1) error-pattern co-occurrence → per-exercise; (2) per-concept mastery heatmap → both; (3) AI error taxonomy → both; (4) comparison-to-class-average → per-student; (5) per-concept progress over time → both. Approve, or revise?
- **AI error taxonomy granularity** — is "Claude returns one short free-text category per failed step (e.g. 'sign error', 'arithmetic mistake', 'notation issue')" sufficient, or do you want a fixed enum?
- **Time-spent-per-exercise UI** — the data is captured (`Submission.timeSpent`) but not surfaced. Show it (a) in the per-student report, (b) in the live dashboard tile, (c) both, (d) not in MVP?
- **Demo seed scope** — does "Reset Demo" wipe only the demo namespace (deterministic UUIDs) and leave teacher-created data alone (recommended)?
- **Test-student UUID** — wire `00000000-0000-0000-0000-000000000001` as a permanent demo-class student record, or leave it as documentation only?
- **Multi-line proofs / canvas pages** — a 10-line proof on one PencilKit canvas may be cramped on iPad portrait. Add a paged or scrollable canvas, or accept single-canvas + smaller writing for MVP?
- **Group naming convention** — should Group names be teacher-free-form (e.g. "Group A", "Renforcement"), or constrained (e.g. only "Niveau 1–5")?
- **Live dashboard refresh model** — Firestore listeners only (recommended), or do we also need an explicit "Pull more" trigger when listeners drop?
- **iPad teacher live dashboard** — required for MVP, or Mac-only is acceptable since teachers usually project the Mac?
- **Apple Charts minimum deployment target** — confirm we can move iOS to 16+ and macOS to 13+ (current targets unverified — manual check on the .pbxproj).
- **Notation strictness — language conventions** — should the AI's notation rules be tuned to French math conventions (e.g. comma decimal separator), international, or both? Default if unspecified: international.
- **README & CLAUDE.md** — am I allowed to update README to remove the false PDF claim, and CLAUDE.md to reflect new Period/Session model after slice 3?
- **Anthropic budget guardrail** — should we cap per-class daily Cloud Function calls (e.g. abort recognize+correct above N submissions/day) for MVP cost safety?
- **Teacher auth in MVP** — keep current Firebase email/password (works), or already swap to magic-link/SSO before first paid sale?
- **Submission rules tightening** — option (a) device-token guard on read (loose), option (b) read only by the teacher who owns the parent class (strict). Pick one.

---

## 6. Risks and assumptions

- **GDPR / minor data**: students are minors with PII (firstName, lastName, deviceToken, handwriting PNGs, audio-free but biometric-adjacent). `firestore.rules` currently allows `read: if true` on submissions — must tighten before any school pilot. Cloud Storage `storage.rules` not audited in this pass; flag for security review. Recommend documenting the data flow in a one-page DPA-ready note.
- **Anthropic costs and rate limits**: a 30-student class submitting 2 exercises in 50 minutes triggers ~60 `recognize_handwriting` + 60 `correct_submission` calls, plus retries. Haiku 4.5 is cheap but bursts hit per-minute limits. Suggest server-side concurrency cap and exponential backoff (`extract_exercise.py` and `recognize_handwriting.py` may need this — `correct_submission.py` already has 3× retry with backoff for persistence).
- **Cloud Function region vs Firestore region**: functions are in `europe-west6`. Confirm Firestore is also in `europe-west6` (or `eur3`/`europe-west`) — cross-region reads inflate latency.
- **Apple Charts requires iOS 16+ / macOS 13+**: project's actual deployment targets are not visible without `.pbxproj` inspection (which the constraints forbid editing). If the targets are below those, the founder must bump them manually as a one-time Xcode task.
- **Period+Session migration**: the existing `Assignment` Firestore documents (and any seeded test data) will be rewritten by slice 3. Plan a one-shot migration script or scrap test data before the migration ships.
- **Offline Storage uploads**: Firestore handles document writes offline, but Cloud **Storage** uploads of PencilKit PNGs do not auto-queue when the device is offline. Mid-submission disconnects need an explicit local queue — addressed in #24.
- **`AssignmentMode` rename to `SessionMode`**: every Firestore document, ViewModel, and view referencing "assignment" will need a sweep. Mitigate by keeping a typealias during migration.
- **App Store: classroom apps targeting minors**: requires "Made for Kids" disclosure or explicit non-targeting; review Apple guidelines before submission. Camera permission for QR scanner needs a kid-friendly purpose string.
- **Demo seed and the live `currentUser`**: seeding must avoid colliding with the signed-in teacher's real classes — use a dedicated "Demo School" teacher account with a known UID and gate the Reset action behind a confirmation dialog.
- **iPad teacher mode parity is large**: every macOS teacher screen has an iPad counterpart today. If iPad live dashboard (#12) is descoped, document it explicitly in the demo script so a salesperson never opens it on iPad in front of a school.
- **README and CLAUDE.md drift**: README claims PDF generation that doesn't exist; CLAUDE.md does not yet describe Period/Session. Both should be updated as part of slice 11 (#28). Until then, treat CLAUDE.md as authoritative for **what is currently in the repo**, not for **what we're about to build**.
- **PencilKit on Mac**: PencilKit is iPad-only. Any future "teacher annotates submission with Pencil" must stay iPad-only. Not in MVP, but a constraint worth knowing.
- **Single-developer staffing**: estimates assume one senior developer. With overlap on multiple slices the order shifts; if external help joins, the natural parallel split is Slice 1 (localization) vs Slices 2–3 (data model) vs Slices 8–9 (analytics + PDF).
- **Bilingual MVP deviates from the original spec line "MVP is English-only; FR/EN toggle is v2"** — adopted at founder's direction on 2026-05-07. The trade-off is small (≈ +1 day for the picker UI; FR translations come free since the current copy is FR), and it preserves the option to demo to either market on day one. Risk: doubles the QA matrix from "EN-only walkthrough" to "FR-only + EN-only + mid-session toggle"; mitigation is to bake both into the test plan from slice 1.
- **Cloud Function-emitted strings** (e.g. error categories from `correct_submission.py`, future notation notes) must be either (a) returned as English keys that the Swift client looks up in its `Localizable.strings`, or (b) returned in two-language form. Pick (a) — keeps Cloud Function language-neutral. Surface in #16 implementation.

---

## Verification (how to confirm each slice end-to-end)

- **Slice 1**: rebuild iOS + macOS targets; with the device locale at FR, walk through teacher signup → create class → add students → create exercise → student login → solve exercise → see feedback. Then, in the teacher profile, toggle to EN and re-run the same walkthrough; every visible string flips. Repeat starting from system EN locale, toggling to FR. Run with the iOS Simulator's right-to-left pseudo-localization sanity check on string lengths.
- **Slice 2**: teacher pastes 12 students from a numeric-bullets list into the iPad bulk-import field, saves, opens each student to set a level 1–5, drags 4 of them into "Group A", verifies in Firestore Console under `/classes/{id}/students` that `level` is set and a new `groups` collection exists.
- **Slice 3**: schedule a Period+Session in the macOS app; verify Firestore documents `/periods/{id}` and `/periods/{id}/sessions/{id}/exercises/{id}` are created; on iPad, sign in as a student in the targeted group at start time, confirm the right exercise appears.
- **Slice 4**: import an exercise from a clean photo; verify the network response from `extract_exercise` includes `competencyIDs`; UI shows them as removable chips with "+ Add" affordance restricted to the catalog.
- **Slice 5**: toggle `notationStrict = false` on a class; submit a malformed but mathematically correct answer; verify `notationNote` is `nil` and the answer is correct. Toggle to `true`; submit the same; verify the banner appears and `correctionResult.stepResults` is still all-true.
- **Slice 6**: print the QR; scan it on a fresh iPad install; confirm the class is identified and the name list loads. Deny camera permission; confirm the manual code-typing fallback still works.
- **Slice 7**: with two physical iPads in a session, watch the macOS dashboard; both tiles update on submit. Force one tile into "Done" by completing all exercises; right-click the tile and push two more; confirm the iPad receives them.
- **Slice 8**: open the per-student report after slice 10's seed runs; every chart renders with non-empty data. Open per-exercise report; co-occurrence chart shows at least one X→Y edge.
- **Slice 9**: Export per-student PDF; open in Preview; verify multiple pages render with charts intact and no clipped text.
- **Slice 10**: fresh install → tap "Use Demo Data" → verify all sample classes, students, exercises, submissions appear without overwriting any pre-existing teacher account. Tap "Reset Demo"; demo namespace is reset, teacher's real data untouched.
- **Slice 11**: airplane-mode test (open exercise, write, hit submit, re-enable network → submission lands); inline-hint coverage check (every actionable control has a one-liner); `firestore.rules` simulator denies cross-class submission reads; `pytest functions/tests` passes including new tests for the other two functions.

---

## Critical files referenced (read or to-modify)

Already read in the planning pass:
- `Core/Services/CorrectionService.swift`
- `Core/Services/ExerciseExtractionService.swift`
- `Core/Services/Recognition/ClaudeRecognitionService.swift`
- `Core/Models/{Student,Classroom,Exercise,Submission,Assignment,AssignmentMode,AssignmentExercise,Competency,Chapter}.swift`
- `Core/Repositories/*` (LevelProgressRepository in particular)
- `MathClass/MathClassApp.swift`, `MathClass/ContentView.swift`
- `MathClass-macOS/MathClass_macOSApp.swift`, `MathClass-macOS/ContentView_macOS.swift`
- `UI/iOS/Views/AddExerciseView.swift`, `UI/iOS/Views/Student/{VerificationView,FeedbackView}.swift`, `UI/iOS/Views/ExerciseView.swift`
- `functions/main.py`, `functions/correct_submission.py`, `functions/recognize_handwriting.py`, `functions/extract_exercise.py`
- `firestore.rules`, `firestore.indexes.json`
- `MathClass.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

To-modify hot list (highest risk of regression):
- `Core/Models/Assignment.swift` → Session/Period split
- `Core/Repositories/AssignmentRepository.swift` → split into SessionRepository + PeriodRepository
- `Core/Services/CorrectionService.swift` + `functions/correct_submission.py` → notation flag
- `MathClass/ContentView.swift` and `MathClass-macOS/ContentView_macOS.swift` → not modified directly but affected by every slice
- `firestore.rules` → expanded for groups, sessions, periods, tightened for submissions
