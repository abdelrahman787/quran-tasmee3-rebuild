/// Riverpod providers with SWAP POINTS (spec §2, §7).
///
/// All external dependencies (ASR, Quran data, session persistence) are
/// injected here. To swap a fake for a real implementation, change exactly
/// one line in this file.
///
/// The app boots with fakes by default so it runs with zero credentials
/// and is fully testable on web preview.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quran_tasmee3_core/recitation/asr_service.dart';
import 'package:quran_tasmee3_core/recitation/matching_engine.dart';
import 'package:quran_tasmee3_core/recitation/recitation_controller.dart';
import 'package:quran_tasmee3_core/recitation/recitation_config.dart';
import 'package:quran_tasmee3_core/review/repositories.dart';
import 'package:quran_tasmee3_core/review/settings.dart';

import '../models/quran_data.dart';
import '../services/fake_asr_service.dart';
import '../services/session_store.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SWAP POINT 1: ASR Service
// ═══════════════════════════════════════════════════════════════════════════
// To use real on-device ASR: replace FakeAsrServiceImpl with StreamingAsrService
// (the onnxruntime-backed implementation from spec §4).
//
// import '../services/streaming_asr_service.dart';
// final asrServiceProvider = Provider<AsrService>((ref) => StreamingAsrService());
// ═══════════════════════════════════════════════════════════════════════════

/// The ASR service — currently a fake that simulates word-by-word recognition.
/// SWAP: replace with real StreamingAsrService for on-device ASR.
final asrServiceProvider = Provider<AsrService>((ref) {
  return FakeAsrServiceImpl();
});

// ═══════════════════════════════════════════════════════════════════════════
// SWAP POINT 2: Session Logger (persistence)
// ═══════════════════════════════════════════════════════════════════════════
// To use Firestore-backed logging: replace InMemorySessionLogger with
// FirestoreSessionLogger.
// ═══════════════════════════════════════════════════════════════════════════

/// The session logger — collects RecordedErrors during a recitation session.
/// SWAP: replace with FirestoreSessionLogger for cloud persistence.
final sessionLoggerProvider = Provider<SessionLogger>((ref) {
  return InMemorySessionLogger();
});

// ═══════════════════════════════════════════════════════════════════════════
// SWAP POINT 3: Review Repositories
// ═══════════════════════════════════════════════════════════════════════════
// Phase 5: The app now overrides these with Hive/SharedPreferences-backed
// implementations via ProviderScope in main().  The in-memory defaults remain
// here so that widget tests work without Hive initialization.
//
// To use Firestore-backed repos: override these providers with Firestore* repos
// in main() instead.
// ═══════════════════════════════════════════════════════════════════════════

final weakItemRepoProvider = Provider<WeakItemRepository>((ref) {
  return InMemoryWeakItemRepository();
});

final planRepoProvider = Provider<PlanRepository>((ref) {
  return InMemoryPlanRepository();
});

final reviewHistoryRepoProvider = Provider<ReviewHistoryRepository>((ref) {
  return InMemoryReviewHistoryRepository();
});

final settingsRepoProvider = Provider<SettingsRepository>((ref) {
  return InMemorySettingsRepository();
});

// ═══════════════════════════════════════════════════════════════════════════
// App State Providers
// ═══════════════════════════════════════════════════════════════════════════

/// Current recitation mode (easy/normal/strict).
final recitationModeProvider = StateProvider<RecitationMode>((ref) {
  return RecitationMode.normal;
});

/// Currently selected surah for recitation.
final selectedSurahProvider = StateProvider<int>((ref) => 1);

/// Session store — holds the current recitation session state for the UI.
final sessionStoreProvider = StateNotifierProvider<SessionStore, SessionState>((ref) {
  return SessionStore();
});

/// Clock provider — returns current epoch ms. Injected for testability.
final clockProvider = Provider<int Function()>((ref) {
  return () => DateTime.now().millisecondsSinceEpoch;
});

// ═══════════════════════════════════════════════════════════════════════════
// Derived providers
// ═══════════════════════════════════════════════════════════════════════════

/// The recitation config derived from the current mode.
final recitationConfigProvider = Provider<RecitationConfig>((ref) {
  final mode = ref.watch(recitationModeProvider);
  return RecitationConfig.presets[mode]!;
});

/// The scope (ExpectedWord list) for the currently selected surah.
final recitationScopeProvider = Provider<List<ExpectedWord>>((ref) {
  final surah = ref.watch(selectedSurahProvider);
  return QuranData.buildScope(surah);
});

/// All 114 surahs are now available (Phase 6: full Quran text loaded from JSON).
final availableSurahsProvider = Provider<List<SurahMeta>>((ref) {
  return QuranData.surahs.toList();
});

/// Debug logger — for kDebugMode only.
void dlog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}
