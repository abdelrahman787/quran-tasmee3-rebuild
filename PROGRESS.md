# Quran Tasmee3 — Rebuild Progress

**Project**: Tasmee3 Trainer (`com.tasmee3.trainer`)
**Specification**: `MASTER_REBUILD_PROMPT.md` (48,856 bytes — 30+ hard-won lessons)
**Date**: 2025-07-01
**Status**: Phases 0–3 complete, web preview functional, ready for native ASR integration

---

## Executive Summary

Quran Tasmee3 has been rebuilt from the ground up following the MASTER_REBUILD_PROMPT specification. The pure-Dart core engine (`quran_tasmee3_core` v0.9.0, 128 tests) has been integrated as a path dependency. A complete Flutter application layer has been built with Riverpod state management, SWAP POINTS for all external dependencies, and a full UI for recitation, review, mushaf browsing, and settings. The app is currently running in web-preview mode with a `FakeAsrService` that simulates word-by-word recognition.

---

## Phase 0 — Core Engine Integration

### Status: COMPLETE

| Task | Result |
|------|--------|
| Clone `quran_tasmee3_core` package | 15 source files, 10 test files |
| Verify all 128 tests pass | 128/128 PASS |
| Add as path dependency in `pubspec.yaml` | `quran_tasmee3_core: path: packages/quran_tasmee3_core` |
| Read and document all public APIs | `AsrService`, `RecitationController`, `SessionReport`, `ReviewService`, `PlanService` |

### Core Package Architecture

```
packages/quran_tasmee3_core/
  lib/
    recitation/
      matching_engine.dart       # Longest-correct-prefix matcher
      normalizer.dart            # Arabic text normalization
      alignment.dart             # Word-level alignment
      recitation_controller.dart # Core orchestrator
      asr_service.dart           # ASR interface contract
      session_logger.dart        # Session logging interface
      session_report.dart        # Post-session report model
      error_taxonomy.dart        # 6 error categories
      expected_word.dart         # Expected word model
    review/
      review_service.dart        # SM-2 spaced repetition
      plan_service.dart          # Review plan generation
      weak_item.dart             # Weak item model
      plan_item.dart             # Plan item model
      review_repositories.dart   # Repository interfaces
  test/
    10 test files, 128 tests
```

### Error Taxonomy (6 categories)

1. **substitution** — wrong word in correct position
2. **order** — correct words in wrong sequence
3. **forget** — missing word (omitted)
4. **pronunciation** — phonetically close but not exact
5. **asrLag** — ASR recognized late (excluded from scoring)
6. **addition** — extra word not in scope

---

## Phase 1 — Flutter Project Scaffolding

### Status: COMPLETE

### Dependencies Added

```yaml
# Path dependency — the locked core engine
quran_tasmee3_core:
  path: packages/quran_tasmee3_core

# State management
flutter_riverpod: 2.5.1

# Local storage
shared_preferences: 2.5.3
hive: 2.2.3
hive_flutter: 1.1.0

# Networking
http: 1.5.0

# Persistence
sqflite: 2.4.1
path_provider: 2.1.5
```

### Gradle Checklist Applied (Spec Section 5)

| Fix | Applied |
|-----|---------|
| JVM heap `-Xmx3G` (down from `-Xmx8G`) | `android/gradle.properties` |
| `gradle.afterProject` force-bump `compileSdk = 35` | `android/build.gradle.kts` |
| No `pickFirst` packaging tricks | Verified clean |
| `sherpa_onnx` + `onnxruntime` coexistence prevention | Architecture decision documented |

### Gradle Properties (`android/gradle.properties`)

```
org.gradle.jvmargs=-Xmx3G -XX:MaxMetaspaceSize=1G -XX:ReservedCodeCacheSize=256m
```

### compileSdk Force-Bump (`android/build.gradle.kts`)

```kotlin
// Force every android-library subproject to compileSdk 35 so third-party
// plugins pinned to an older compileSdk don't fail AndroidX AAR metadata
// checks. gradle.afterProject fires AFTER each project's own build script,
// so this always wins regardless of evaluation order.
// (spec §3.14 — verified working pattern for AGP 9)
gradle.afterProject {
    extensions.findByType<com.android.build.api.dsl.LibraryExtension>()?.run {
        if ((compileSdk ?: 0) < 35) compileSdk = 35
    }
}
```

---

## Phase 2 — Riverpod Provider Architecture

### Status: COMPLETE

### SWAP POINTS (`lib/app/providers.dart`)

All external dependencies are injected via Riverpod providers. Swapping fake to real requires changing exactly one line per dependency.

| Provider | Current Implementation | Real Implementation (Future) |
|----------|----------------------|------------------------------|
| `asrServiceProvider` | `FakeAsrServiceImpl()` | `OnnxRuntimeAsrService` (native) |
| `sessionLoggerProvider` | `InMemorySessionLogger()` | `FirestoreSessionLogger` |
| `weakItemRepoProvider` | In-memory | `HiveWeakItemRepository` |
| `planRepoProvider` | In-memory | `HivePlanRepository` |
| `reviewHistoryRepoProvider` | In-memory | `HiveReviewHistoryRepository` |
| `settingsRepoProvider` | In-memory | `SharedPreferencesSettingsRepository` |

### State Providers

- `recitationModeProvider` — easy / normal / strict
- `selectedSurahProvider` — currently selected surah
- `sessionStoreProvider` — `SessionStore` (StateNotifier)
- `clockProvider` — injectable clock for testing
- `recitationConfigProvider` — derived from mode
- `recitationScopeProvider` — `List<ExpectedWord>` from selected surah
- `availableSurahsProvider` — surah metadata list

---

## Phase 3 — UI Implementation

### Status: COMPLETE

### App Structure (12 Dart files)

```
lib/
  main.dart                              # Tasmee3App with ProviderScope
  app/
    app_theme.dart                       # Material Design 3, Islamic color palette
    providers.dart                       # Riverpod providers + SWAP POINTS
  models/
    quran_data.dart                      # 114 surah metadata, 9 embedded ayah texts
  services/
    session_store.dart                   # StateNotifier bridging RecitationController
    fake_asr_service.dart                # Web-preview ASR simulation
  features/
    home/home_screen.dart                # Bottom nav (Mushaf, Recite, Review, Settings)
    mushaf/mushaf_screen.dart            # Surah browser with expandable cards
    recitation/recitation_screen.dart    # Live word-by-word coloring
    report/report_screen.dart            # Post-session score + error breakdown
    review/review_screen.dart            # SM-2 review plan queue
    settings/settings_screen.dart        # Recitation mode + review settings
```

### Screen Details

#### Home Screen
- Bottom navigation with 4 tabs: Mushaf, Recite, Review, Settings
- `IndexedStack` for tab content preservation

#### Mushaf Screen
- Surah browser listing all 114 surahs with metadata
- Expandable cards showing embedded ayah text
- "Start Recitation" button sets `selectedSurahProvider` and switches to Recite tab

#### Recitation Screen (Core Feature)
- Live word-by-word coloring using `RecitationController`
- Word pill states: unrevealed, revealed, error, soft error, pronunciation, cursor
- Status bar: listening / matching / revealing / error / completed / paused
- Controls: pause/resume, reveal next word, reveal full ayah, end session
- End session navigates to Report screen with `SessionReport`

#### Report Screen
- Score card with percentage circle
- Error breakdown by all 6 categories
- Per-ayah accuracy with progress bars
- Detailed error list (expected vs recognized text)

#### Review Screen
- Uses `ReviewService.rebuildAutoPlan()` from core
- Shows: today's queue, upcoming reviews, mastered count
- Plan item tiles with status, due date, last score

#### Settings Screen
- Recitation mode selector (easy/normal/strict) with threshold display
- Review settings: daily target, weakness threshold, mastery horizon, merge contiguous
- About section

### Theme (`lib/app/app_theme.dart`)

| Color | Hex | Usage |
|-------|-----|-------|
| `primaryGreen` | `#1B6B4C` | Primary brand |
| `goldAccent` | `#D4A843` | Accent / highlights |
| `parchment` | `#FBF8F0` | Background |
| `wordUnrevealed` | — | Unrevealed words |
| `wordRevealed` | — | Correctly recited words |
| `wordError` | — | Substitution / forget errors |
| `wordSoftError` | — | Minor errors |
| `wordPronunciation` | — | Pronunciation errors |
| `wordCurrent` | — | Current cursor position |

### Quran Data (`lib/models/quran_data.dart`)

- 114 surah metadata entries (name, number, ayah count, revelation type)
- Embedded Uthmani ayah text for 9 surahs:
  - Al-Fatihah (1), Al-Asr (103), Al-Kawthar (108), Al-Kafirun (109),
  - An-Nasr (110), Al-Masad (111), Al-Ikhlas (112), Al-Falaq (113), An-Nas (114)
- `QuranData.buildScope(surah)` returns `List<ExpectedWord>` for recitation

### Fake ASR Service (`lib/services/fake_asr_service.dart`)

- Implements `AsrService` interface from core
- `setScope(List<ExpectedWord>)` — receives expected words to "recognize"
- Emits words with configurable delay (1200ms) and confidence (0.92)
- Simulates natural speech rhythm (sometimes 2-3 words at once)
- Enables full end-to-end testing of recitation flow in web preview

### Session Store (`lib/services/session_store.dart`)

- `SessionStore extends StateNotifier<SessionState>`
- Bridges pure-Dart `RecitationController` to Riverpod reactive state
- Methods: `startSession()`, `submitAsrResult()`, `pause()`, `resume()`, `revealNextWord()`, `revealFullAyah()`, `stopAndReport()`, `flushAsr()`
- `Timer.periodic` for silence checking

---

## Build & Test Results

| Check | Result |
|-------|--------|
| Core tests (`dart test`) | 128/128 PASS |
| App tests (`flutter test`) | 1/1 PASS |
| Static analysis (`flutter analyze`) | 0 errors (deprecation infos only) |
| Web build (`flutter build web --release`) | SUCCESS (39s) |
| Android config | Package name `com.tasmee3.trainer` synced |

---

## Issues Resolved During Build

| Issue | Fix |
|-------|-----|
| Apostrophe in `An-Nazi'at` broke string literal | Changed to `An-Naziat` |
| `ExpectedWord` not imported in providers | Added `matching_engine.dart` import |
| `Timer` undefined in session_store | Added `import 'dart:async'` |
| `SessionState` not imported in recitation_screen | Added `session_store.dart` import |
| Undefined `scope` variable in `_buildStatusBar` | Passed `totalWords` parameter |
| `findAncestorStateOfType` broken cross-widget state | Replaced with provider update + snackbar |
| Unnecessary `borderColor!` null assertion | Removed `!` (already non-null in branch) |

---

## What's Next

### Phase 4 — Native ASR Integration (Android)

1. **Add `onnxruntime` Flutter package** (NOT `sherpa_onnx` — they conflict in same APK)
2. **Download FastConformer-CTC streaming model** from `Saboorhsn/quran-stt-onnx` (Q8 variant)
3. **Implement `OnnxRuntimeAsrService`** — implements `AsrService` interface
4. **Hand-roll cache plumbing** for streaming inference
5. **Pure-Dart energy VAD** for voice activity detection
6. **Swap `asrServiceProvider`** from `FakeAsrServiceImpl` to `OnnxRuntimeAsrService`

### Phase 5 — Persistent Storage

1. Implement `HiveWeakItemRepository`, `HivePlanRepository`, `HiveReviewHistoryRepository`
2. Implement `SharedPreferencesSettingsRepository`
3. Swap all repository providers from in-memory to persistent implementations

### Phase 6 — Full Quran Data

1. Embed or stream complete Uthmani Quran text (all 114 surahs, 6236 ayahs)
2. Consider asset bundling strategy (compressed JSON vs SQLite)

### Phase 7 — Polish & Production

1. Arabic typography optimization
2. Audio feedback (correct/error sounds)
3. Haptic feedback on errors
4. Export/import review data
5. Firebase sync (optional, behind a flag)

---

## Architecture Decisions Log

1. **ASR: `onnxruntime` direct, not `sherpa_onnx`** — The two packages ship conflicting native libraries and cannot coexist in the same APK. `onnxruntime` gives lower-level control needed for streaming CTC inference.

2. **Pure-Dart core, never modified for app bugs** — The `quran_tasmee3_core` package is a sealed engine with 128 tests. All app-layer bugs are fixed in the app layer, never by patching the core.

3. **Riverpod with explicit SWAP POINTS** — Every external dependency (ASR, storage, logging) is behind a provider. Moving from fake to real is a one-line change per provider.

4. **FakeAsrService for web preview** — Web platform cannot access native ASR. A fake service that simulates word-by-word recognition enables full UI testing in the browser.

5. **JVM heap 3G not 8G** — The spec's hard-won lesson: `Xmx8G` causes OOM kills on CI and some dev machines. 3G is sufficient and safer.

6. **`gradle.afterProject` compileSdk force-bump** — Plugin subprojects often declare older compileSdk values. A single `afterProject` hook forces all to 35, preventing silent failures.

---

## File Modification Ledger

| File | Action | Description |
|------|--------|-------------|
| `packages/quran_tasmee3_core/` | Copied | Entire pure-Dart core engine, 128 tests |
| `pubspec.yaml` | Modified | Added core path dep + all app dependencies |
| `lib/models/quran_data.dart` | Created | 114 surah metadata + 9 embedded ayah texts |
| `lib/app/app_theme.dart` | Created | MD3 theme with Islamic color palette |
| `lib/app/providers.dart` | Created | Riverpod providers with SWAP POINTS |
| `lib/services/session_store.dart` | Created | StateNotifier bridging RecitationController |
| `lib/services/fake_asr_service.dart` | Created | Fake ASR for web preview |
| `lib/main.dart` | Modified | Tasmee3App with ProviderScope |
| `lib/features/home/home_screen.dart` | Created | Bottom nav with 4 tabs |
| `lib/features/mushaf/mushaf_screen.dart` | Created | Surah browser |
| `lib/features/recitation/recitation_screen.dart` | Created | Live word coloring recitation |
| `lib/features/report/report_screen.dart` | Created | Post-session report |
| `lib/features/review/review_screen.dart` | Created | SM-2 review plan |
| `lib/features/settings/settings_screen.dart` | Created | Settings |
| `android/gradle.properties` | Modified | JVM heap 8G to 3G |
| `android/build.gradle.kts` | Modified | Added gradle.afterProject compileSdk force-bump |
| `test/widget_test.dart` | Modified | Updated to test bottom nav rendering |
| `.gitignore` | Modified | Added secrets and model assets exclusions |

---

## Completion Checklist

- [x] Phase 0: Clone quran_tasmee3_core, verify 128 tests pass
- [x] Generate app info (Tasmee3 Trainer, com.tasmee3.trainer)
- [x] Read all core public API files
- [x] Phase 1: Create Flutter project with path dependency to core
- [x] Set up Riverpod providers with swap points
- [x] Apply Gradle checklist (Section 5): JVM heap, compileSdk force-bump
- [x] Phase 3: Build Mushaf viewer screen
- [x] Phase 3: Build Recitation screen with live word coloring
- [x] Phase 3: Build Report screen
- [x] Phase 3: Build Review screen (SM-2)
- [x] Phase 3: Build Settings screen
- [x] Set up ASR architecture with web-compatible fakes
- [x] Generate and integrate app icon
- [x] Build web app and verify tests pass
- [x] Initial git commit
- [x] Write PROGRESS.md file
- [ ] Push to GitHub
- [ ] Phase 4: Native ASR integration (onnxruntime + FastConformer-CTC)
- [ ] Phase 5: Persistent storage (Hive repositories)
- [ ] Phase 6: Full Quran data (all 114 surahs)
- [ ] Phase 7: Polish & production readiness
