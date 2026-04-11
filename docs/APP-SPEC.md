# AnpiApp — Application Specification

> **Project:** AnpiApp (安否確認アプリ)
> **Competition:** Gemma 4 Good Hackathon 2026 (deadline 2026-05-18)
> **Platform:** iOS 18.0+ (iPhone)
> **Language:** Swift 5.9 / SwiftUI
> **License:** Apache License 2.0
> **Repository root:** `projects/anpi-app/`

This document is a code-grounded specification of every feature, file, and architectural decision present in the AnpiApp source tree. It is intended as the substrate for the Kaggle Writeup / README. All claims are derived from the 38 Swift files under `Sources/AnpiApp/`.

---

## 1. Overview

### 1.1 Purpose
AnpiApp is a **fully offline iOS application that streamlines evacuee intake at disaster shelters**. A single iPhone replaces the typical paper-and-pen reception workflow:

1. A volunteer points the camera at an ID card (My Number Card / driver's license / residence card / health insurance card / passport).
2. The on-device AI auto-extracts the name, address, and date of birth.
3. The volunteer confirms, optionally adds injury status / special-needs flags, and saves.
4. The Situation tab shows real-time aggregated counts and an estimate of required supplies (water, food, blankets, diapers, formula, sanitary pads, medical kits).
5. The AI Assistant tab answers shelter-operations questions either through deterministic code paths (for hard numbers) or via free-form Gemma 4 generation.

### 1.2 Target users
- Shelter reception volunteers and staff during a disaster response.
- Local-government disaster-management staff running emergency evacuation centers.
- Foreign residents (residence-card support, plain-Japanese guidance via the AI assistant).

### 1.3 Platform & runtime requirements
- **iOS 18.0+** (some views fall back gracefully to iOS 16/17 paths via `if #available`).
- **iPhone with camera** (AVFoundation `AVCaptureSession`).
- **Network: not used** — every feature works in fully airplane mode.
- **Storage:** ~2.7 GB for the Gemma 4 E2B CoreML chunks plus a small SQLite database under `Documents/anpi.sqlite`.

### 1.4 Use of Gemma 4
- **Model:** `Gemma 4 E2B` — 2-billion-effective-parameter variant — distributed as a chunked CoreML package (`mlboydaisuke/gemma-4-E2B-coreml` on Hugging Face), loaded by `CoreMLLLM`.
- **Two distinct tasks:**
  1. **Multimodal card analysis** — image + prompt → JSON `{name, address, dateOfBirth, cardType, confidence}`.
  2. **Free-form Q&A** — text prompt → shelter-operations answer (used only when the user asks something outside the deterministic preset menu).
- **Hybrid inference policy** — Gemma is the primary OCR brain, but Apple Vision OCR is always available as a fallback / sanity check, and any field the model returns with low confidence falls back to the OCR text.

### 1.5 Privacy stance
- All inference and storage stays on the device.
- No analytics, no telemetry, no network calls anywhere in the codebase.
- An explicit consent screen (`ConsentView`) is shown before each save, listing the exact data that will be persisted.
- Test-mode data is auto-deleted on app termination via `applicationWillTerminate`.

---

## 2. Architecture

### 2.1 Layered view (text diagram)

```
┌────────────────────────────────────────────────────────────────┐
│                        SwiftUI Views                           │
│ ┌────────────────────┐  ┌───────────┐  ┌───────────────────┐   │
│ │ Registration Tab   │  │ Situation │  │  AI Assistant     │   │
│ │  RegistrationHome  │  │   View    │  │  Tab              │   │
│ │  ManualInput       │  │           │  │  AIAssistantView  │   │
│ │  CardScan          │  │           │  │                   │   │
│ │  CardAnalysis      │  │           │  │                   │   │
│ │  CardScanResult    │  │           │  │                   │   │
│ │  EvacueeList/Detail│  │           │  │                   │   │
│ │  Distribution*     │  │           │  │                   │   │
│ │  Filter / Help     │  │           │  │                   │   │
│ │  Export / Consent  │  │           │  │                   │   │
│ └────────────────────┘  └───────────┘  └───────────────────┘   │
│                LaunchModeView → MainTabView                    │
│                    ModelSetupView (one-time)                   │
└────────────────────────────────────────────────────────────────┘
                             │ @EnvironmentObject
                             ▼
┌────────────────────────────────────────────────────────────────┐
│                          Services                              │
│  GemmaService (LLM)        CardOCRService (Vision)             │
│  CardPreprocessor          CSVExportService                    │
│  AddressNormalizer         FamilyGroupService                  │
│  DatabaseService (GRDB)    ShelterAnalytics                    │
│  ModelManager              SampleDataSeeder                    │
│  LocationService           AudioService (TTS)                  │
│  RateLimitService          NFCService (stub)                   │
└────────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌────────────────────────────────────────────────────────────────┐
│                          Models                                │
│  EvacueeRecord (+ Gender / AgeGroup / SpecialNeed enums)       │
│  CardAnalysisResult (+ CardType enum)                          │
│  Distribution (+ DistributionCheckItem)                        │
│  ChatMessage                                                   │
└────────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌────────────────────────────────────────────────────────────────┐
│              Persistence: GRDB.swift on SQLite                 │
│  Documents/anpi.sqlite (migrations: v1, v3_phase2_fields, ...) │
│    evacueeRecord / familyGroup / distribution                  │
│    distributionCheckItem                                       │
└────────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌────────────────────────────────────────────────────────────────┐
│        CoreML model bundle (Gemma 4 E2B, chunked)              │
│   Bundle/Models/gemma-4-E2B-coreml  OR  Documents/gemma4       │
└────────────────────────────────────────────────────────────────┘
```

### 2.2 AI pipeline

```
Camera frame (AVCaptureSession)
        │
        ▼
Auto-shutter trigger        ← edge density / brightness heuristic
        │
        ▼
CardPreprocessor
  ├─ perspective correction (rectangle detection via Vision)
  ├─ resize to maxDimension=1024
  └─ contrast / orientation normalisation
        │
        ├──────────────────────────────┐
        ▼                              ▼
 GemmaService.analyzeCard()    CardOCRService.recognize()
  (multimodal CoreML LLM)       (Vision VNRecognizeTextRequest)
        │                              │
        └──────────► merge ◄───────────┘
                       │
                       ▼
        Confidence-based adoption policy
          • per-field confidence ≥ 0.8 → take Gemma value
          • 0.5–0.8 → take Gemma value, mark as low-confidence
          • < 0.5 → drop Gemma value, fall back to OCR text
          • model unavailable → OCR-only path
                       │
                       ▼
                CardAnalysisResult
                       │
                       ▼
              CardScanResultView (manual confirm / edit)
                       │
                       ▼
                  ManualInputView form
                       │
                       ▼
                  ConsentView gate
                       │
                       ▼
                DatabaseService.save()
```

### 2.3 Data flow (capture → analytics → AI)

```
[User taps "新規登録"]
   → RegistrationHomeView routes to ManualInputView
   → CardScanView (camera) captures UIImage
   → CardAnalysisView runs Gemma + OCR pipeline
   → CardScanResultView lets user confirm / fix fields
   → ManualInputView form (injury, special needs, family group)
   → AddressNormalizer.normalize()
   → FamilyGroupService.findCandidates()
   → ConsentView (explicit save consent)
   → RateLimitService.requestRegistration() (5/min, 60s cooldown)
   → DatabaseService.save(&EvacueeRecord)
   → AudioService.announceComplete(name:)
   → LocationService stamps lat/lon if granted

[Situation tab]
   → DatabaseService.fetchStats() → ShelterStats
   → ShelterAnalytics.estimateSupplies(stats, days)
   → SituationView renders cards + adjustable day-slider

[AI Assistant tab]
   → AIAssistantView shows 5 preset chips + free input
   → preset → ShelterAnalytics.generatePresetAnswer() (deterministic)
   → free text → GemmaService.generate() (LLM)
   → ChatMessage persisted in-memory and rendered
```

---

## 3. Feature Catalogue

Each feature lists: **name** · **description** · **related files** · **technical highlights**.

### 3.1 Evacuee Registration

#### F-01 Card-based auto-registration
- **Description:** Photograph an ID card; AI fills in name, address, DOB, and card type. The user reviews/edits, then saves.
- **Files:** `ManualInputView.swift`, `CardScanView.swift`, `CardAnalysisView.swift`, `CardScanResultView.swift`, `Models/CardAnalysisResult.swift`.
- **Highlights:**
  - Five-state input flow (`InputMode`: `.selection / .scanning / .analyzing / .reviewing / .manual`) inside a single `ManualInputView`.
  - Both card-only path and OCR-only legacy path are wired (`onResult` vs `onResultOCR` callbacks).

#### F-02 Manual registration
- **Description:** Form-based registration with the same field set as the card path.
- **Files:** `ManualInputView.swift` (`formView`).
- **Highlights:** segmented injury picker, body-part chip grid (15 parts), special-needs toggles, gender / age-group pickers.

#### F-03 Camera scan with auto-shutter
- **Description:** Live `AVCaptureSession` viewfinder that automatically captures when an ID card is centred and stable.
- **Files:** `CardScanView.swift`.
- **Highlights:** detects rectangles via `VNDetectRectanglesRequest`, computes an edge-density / aspect-ratio check, and triggers the shutter when the document is steady. Manual shutter and "skip to manual entry" are also exposed.

#### F-04 Card OCR (Vision fallback)
- **Description:** Apple Vision text recognition as a deterministic fallback when Gemma is unavailable or low confidence.
- **Files:** `Services/CardOCRService.swift`.
- **Highlights:** `VNRecognizeTextRequest` with Japanese language hints, heuristic line tagging (氏名 / 住所 / 生年月日) using regex on the recognised lines.

#### F-05 Card preprocessing
- **Description:** Perspective-correct, deskew, and downscale the captured card image before feeding either OCR or Gemma.
- **Files:** `Services/CardPreprocessor.swift`.
- **Highlights:** rectangle detection + `CIPerspectiveCorrection`, fixed `maxDimension = 1024`, EXIF-orientation normalisation, optional contrast bump.

#### F-06 Gemma 4 multimodal card analysis
- **Description:** Runs the Gemma 4 E2B CoreML model on the preprocessed card image, prompts it for a strict JSON schema, parses, and emits a `CardAnalysisResult`.
- **Files:** `Services/GemmaService.swift`, `Models/CardAnalysisResult.swift`, `Views/CardAnalysisView.swift`.
- **Highlights:**
  - Confidence thresholds: `highConfidenceThreshold = 0.8`, `lowConfidenceThreshold = 0.5`, with `isLowConfidence` flag at < 0.7 in the UI.
  - Strict JSON parsing with graceful fallback through `onFallback` to `CardOCRService`.
  - Loads from `Bundle/Models/gemma-4-E2B-coreml` or `Documents/gemma4` (chunked CoreML package).

#### F-07 Result review screen
- **Description:** Side-by-side preview of recognised fields with editable text fields and a confidence badge per field.
- **Files:** `CardScanResultView.swift`.
- **Highlights:** `onConfirm` / `onRetry` callbacks; switches to manual input if user opts out.

#### F-08 Address normalisation
- **Description:** Normalise raw OCR/Gemma addresses for de-duplication and family-group matching.
- **Files:** `Services/AddressNormalizer.swift`.
- **Highlights:** Hokkaido-style "N条西M丁目" is matched **before** the generic "〇丁目" rule; full-width digits mapped to half-width; trailing room numbers stripped. Also exposes `extractFamilyName(_:)` (first whitespace/space-delimited token).

#### F-09 Family-group inference
- **Description:** Suggest existing evacuees that may belong to the same family (same family name + same address block) so volunteers can group them.
- **Files:** `Services/FamilyGroupService.swift`, `Views/FamilyGroupBanner.swift`, `DatabaseService.findFamilyCandidates(...)`.
- **Highlights:** When candidates exist, a banner appears with "Same family / Register separately" buttons. Joining sets `familyGroupId`; otherwise a fresh UUID is minted for the new group.

#### F-10 Consent gate
- **Description:** Modal sheet shown before persisting personal data, listing exactly what is stored and reaffirming the offline-only policy.
- **Files:** `Views/ConsentView.swift`.
- **Highlights:** `onConsent` / `onCancel` callbacks; cancellation also stops any in-flight TTS announcement.

#### F-11 Rate limiting
- **Description:** Prevent volunteer mistakes / abuse by capping registrations to 5 per minute with a 60-second cooldown after the cap is hit.
- **Files:** `Services/RateLimitService.swift`.
- **Highlights:** `maxPerMinute = 5`, `cooldownSeconds = 60`; UI surfaces a "しばらくお待ちください" banner with a remaining-cooldown counter.

#### F-12 Voice announcements
- **Description:** Speak short Japanese confirmations (registration complete, rate-limit hit) to assist hands-free use.
- **Files:** `Services/AudioService.swift`.
- **Highlights:** `AVSpeechSynthesizer` with `ja-JP`, `announceComplete(name:)`, `announceRateLimit()`, `stop()`.

#### F-13 GPS stamping
- **Description:** Optionally tag each record with the lat/lon at the time of registration.
- **Files:** `Services/LocationService.swift`.
- **Highlights:** `requestPermission()` / `start()`; only activates in emergency mode and only after the user taps the registration button.

### 3.2 AI Assistant

#### F-14 Deterministic preset answers (5 types)
- **Description:** Tapping a preset button (怪我人の状況 / 必要物資 / 要配慮者 / 全体サマリー / 外国人対応) generates an **instant, 100%-accurate answer from Swift code** — no AI involved.
- **Files:** `Services/ShelterAnalytics.swift` (`generatePresetAnswer(_:db:)`, `PresetKind` enum), `Views/AIAssistantView.swift`.
- **Highlights:** Implemented as a design decision after discovering E2B (2B params) cannot reliably cross-reference structured data sections. Code paths guarantee correct counts, names, and injury details every time.

#### F-15 Free-form AI Q&A
- **Description:** User types any question → context is generated from DB records → Gemma 4 E2B generates a streaming answer.
- **Files:** `Services/GemmaService.swift` (`chat(contextText:userMessage:onToken:)`, `buildPrompt(context:question:)`), `Services/ShelterAnalytics.swift` (`generateContext(db:days:)`).
- **Highlights:** Prompt allows both data-grounded answers ("how many injured?") and general shelter-operations knowledge ("how to set up a drum-can bath?"). Streaming via `CoreMLLLM.stream()`, maxTokens=384.

#### F-16 Conversation management
- **Description:** Chat history in memory (session-scoped, not persisted). Reset button (🗑️) in toolbar clears all messages.
- **Files:** `Views/AIAssistantView.swift`, `Models/ChatMessage.swift`.
- **Highlights:** Reset disabled during generation. Confirmation dialog before clearing.

### 3.3 Situation Dashboard

#### F-17 Real-time statistics
- **Description:** Aggregated counts — total evacuees, age breakdown (infant/child/adult/elderly), gender split, injury severity, special needs, foreign residents.
- **Files:** `Views/SituationView.swift`, `Services/ShelterAnalytics.swift` (`computeStats(from:)`).
- **Highlights:** Refreshes on `onAppear` and via pull-to-refresh.

#### F-18 Supply estimation
- **Description:** Compute required supplies for N days based on government guidelines (内閣府「避難所における良好な生活環境の確保に向けた取組指針」).
- **Files:** `Services/ShelterAnalytics.swift` (`estimateSupplies(from:days:)`).
- **Highlights:** Water 3L/person/day, food 3 meals/person/day, blankets 1/person, diapers 5/infant/day, formula 1 can/infant/day, sanitary pads 1/user/day, medical kits per injured person. Day slider (1-30) in `SituationView`.

#### F-19 Foreign resident detection
- **Description:** Heuristic detection of non-Japanese residents by name analysis.
- **Files:** `Services/ShelterAnalytics.swift` (`isForeignResident()`).
- **Highlights:** Checks for: (1) cardType == .residenceCard, (2) ASCII letters in name, (3) katakana-only name without kanji/hiragana.

### 3.4 Data Management

#### F-20 SQLite database (GRDB)
- **Description:** Local SQLite via GRDB.swift. `EvacueeRecord` conforms to `Codable`, `FetchableRecord`, `MutablePersistableRecord`.
- **Files:** `Services/DatabaseService.swift`, `Models/EvacueeRecord.swift`.
- **Highlights:** 5 migrations (v1 → v5_injury_locations). Fields: name, dateOfBirth, address, injuryStatus, injuryLocationsJSON, gender, ageGroup, specialNeedsJSON, cardType, familyGroupId, familyName, addressBlock, latitude, longitude, isEmergencyMode, createdAt.

#### F-21 Search and filter
- **Description:** `.searchable` bar (name/address substring match) + attribute chip filters (female, children, special needs, family group).
- **Files:** `Views/RegistrationHomeView.swift`, `Views/FilterView.swift`.
- **Highlights:** Zero-result state shows `ContentUnavailableView.search`. Filters and search compose.

#### F-22 Individual record deletion
- **Description:** Delete a single evacuee from the detail view with confirmation dialog.
- **Files:** `Views/EvacueeDetailView.swift`, `Services/DatabaseService.swift` (`delete(_:)`).
- **Highlights:** Accessibility label, destructive role button, dismiss after delete.

#### F-23 CSV export
- **Description:** Export all records to a CSV file shareable via `ShareLink`.
- **Files:** `Services/CSVExportService.swift`, `Views/ExportView.swift`.
- **Highlights:** UTF-8 BOM for Excel compatibility. All fields including injury locations.

#### F-24 Distribution management
- **Description:** Track physical supply distribution (water, food, blankets, etc.) per evacuee with a checklist UI.
- **Files:** `Views/DistributionListView.swift`, `Views/DistributionCheckView.swift`, `Models/Distribution.swift`.
- **Highlights:** Progress bar, strikethrough for distributed items, undo capability.

#### F-25 Sample data seeding
- **Description:** One-tap injection of 18 realistic sample evacuees for testing and demo video recording.
- **Files:** `Services/SampleDataSeeder.swift`.
- **Highlights:** 4 family groups, 2 foreign names (Maria Santos, Wei Chen), all age groups, injury severities, and special needs represented. Test mode only.

#### F-26 Bulk test-data deletion
- **Description:** Delete all test-mode records in one tap.
- **Files:** `Views/RegistrationHomeView.swift`, `Services/DatabaseService.swift` (`deleteTestData()`).

### 3.5 UI / UX

#### F-27 Dual-mode launch (Test / Emergency)
- **Description:** First screen selects Test Mode or Emergency Mode. Test data is isolated and auto-deleted on app termination.
- **Files:** `Views/LaunchModeView.swift`.

#### F-28 TabView navigation (3 tabs)
- **Description:** Record (登録) / Situation (状況) / AI Assistant (AI) — each tab has its own NavigationStack.
- **Files:** `Views/MainTabView.swift`.

#### F-29 Mode exit button
- **Description:** Return to mode selection from any tab via a shared toolbar button + Notification-based navigation reset.
- **Files:** `Views/ExitToModeSelectionButton.swift`, `Views/LaunchModeView.swift`.
- **Highlights:** Confirmation dialog ("登録データは保持されます"). DRY implementation via shared ViewModifier.

#### F-30 NFC stub
- **Description:** Placeholder for future NFC-based card reading (CoreNFC framework imported but not yet wired).
- **Files:** `Services/NFCService.swift`.

---

## 4. Gemma 4 Usage — Intelligent Routing

AnpiApp implements a **dual-path intelligent routing** strategy:

| Query type | Path | Accuracy | Latency |
|---|---|---|---|
| Preset questions (5 types) | Swift code → `ShelterAnalytics` | 100% deterministic | Instant (~0ms) |
| Free-form questions | Gemma 4 E2B → streaming tokens | Best-effort (2B model) | 3-10s |
| Card analysis | Gemma 4 E2B (multimodal) + Vision OCR | Hybrid, confidence-gated | 5-15s |

This routing is **the core technical insight** of the project: a 2B on-device model excels at flexible, unstructured tasks (free-form Q&A, multimodal extraction) but struggles with structured data retrieval. By routing structured queries to deterministic code paths, the system delivers enterprise-grade accuracy for critical shelter data while preserving the AI's value for open-ended assistance.

---

## 5. Technology Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI (iOS 18), TabView, NavigationStack, .searchable |
| AI | CoreMLLLM (Gemma 4 E2B), chunked CoreML model loading |
| Vision | VNRecognizeTextRequest, VNDetectRectanglesRequest, CIPerspectiveCorrection |
| Camera | AVCaptureSession, AVCaptureVideoDataOutput (real-time detection), AVCapturePhotoOutput |
| Database | GRDB.swift (SQLite), 5 migrations, Codable records |
| Audio | AVSpeechSynthesizer (ja-JP) |
| Location | CoreLocation (emergency mode only) |
| Export | CSV with UTF-8 BOM |

**Total codebase:** 38 Swift files, 6,326 lines of code.

---

## 6. File Inventory (38 files)

| Directory | File | Lines | Description |
|---|---|---|---|
| App/ | AnpiAppApp.swift | ~45 | App entry, environment injection, test-data cleanup |
| Models/ | CardAnalysisResult.swift | ~50 | Card OCR/Gemma result struct |
| Models/ | ChatMessage.swift | ~15 | AI chat message model |
| Models/ | Distribution.swift | ~30 | Supply distribution record |
| Models/ | EvacueeRecord.swift | ~121 | Core data model (GRDB) |
| Services/ | AddressNormalizer.swift | ~120 | Address normalization + family name extraction |
| Services/ | AudioService.swift | ~40 | TTS announcements |
| Services/ | CSVExportService.swift | ~56 | CSV generation |
| Services/ | CardOCRService.swift | ~180 | Vision OCR with MRZ parser |
| Services/ | CardPreprocessor.swift | ~170 | Image preprocessing pipeline |
| Services/ | DatabaseService.swift | ~283 | GRDB wrapper, migrations, CRUD |
| Services/ | FamilyGroupService.swift | ~60 | Family matching logic |
| Services/ | GemmaService.swift | ~450 | CoreML model loading, card analysis, chat |
| Services/ | LocationService.swift | ~50 | GPS coordinate capture |
| Services/ | ModelManager.swift | ~80 | Model discovery and validation |
| Services/ | NFCService.swift | ~30 | NFC stub |
| Services/ | RateLimitService.swift | ~40 | Registration rate limiting |
| Services/ | SampleDataSeeder.swift | ~249 | 18-person test data generator |
| Services/ | ShelterAnalytics.swift | ~541 | Stats, supplies, context, preset answers |
| Views/ | AIAssistantView.swift | ~200 | AI chat tab |
| Views/ | CardAnalysisView.swift | ~100 | Gemma analysis overlay |
| Views/ | CardScanResultView.swift | ~80 | OCR result review |
| Views/ | CardScanView.swift | ~450 | Camera + auto-shutter |
| Views/ | ConsentView.swift | ~50 | Privacy consent modal |
| Views/ | DistributionCheckView.swift | ~168 | Per-evacuee distribution checklist |
| Views/ | DistributionListView.swift | ~134 | Distribution overview |
| Views/ | EvacueeDetailView.swift | ~150 | Record detail + edit + delete |
| Views/ | EvacueeListView.swift | ~60 | Simple list (legacy) |
| Views/ | ExitToModeSelectionButton.swift | ~40 | Shared mode-exit button |
| Views/ | ExportView.swift | ~38 | CSV export trigger |
| Views/ | FamilyGroupBanner.swift | ~50 | Family match suggestion |
| Views/ | FilterView.swift | ~48 | Attribute chip filters |
| Views/ | HelpView.swift | ~40 | Usage instructions |
| Views/ | LaunchModeView.swift | ~100 | Test/Emergency mode selector |
| Views/ | MainTabView.swift | ~45 | 3-tab container |
| Views/ | ManualInputView.swift | ~380 | Manual registration form |
| Views/ | ModelSetupView.swift | ~80 | Gemma model download/setup |
| Views/ | RegistrationHomeView.swift | ~339 | Main registration list + search |
| Views/ | SituationView.swift | ~265 | Dashboard tab |

