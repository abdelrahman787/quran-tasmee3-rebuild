/// Quran Tasmee3 — Main entry point.
///
/// Offline-first Flutter app for Quran memorization testing.
/// A student recites from memory; on-device streaming ASR reveals words
/// live and flags mistakes; a post-session report feeds an SM-2
/// spaced-repetition review planner.
///
/// Architecture (spec §2, §7):
/// - packages/quran_tasmee3_core: pure-Dart engine (matching, SM-2, reports)
/// - lib/app/providers.dart: Riverpod providers with SWAP POINTS
/// - lib/features/*: Flutter UI screens
/// - lib/services/*: app-layer services (ASR, session store)
/// - lib/services/persistence/*: Hive + SharedPreferences repos (Phase 5)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/app_theme.dart';
import 'app/providers.dart';
import 'features/home/home_screen.dart';
import 'services/persistence/hive_repositories.dart';
import 'services/persistence/prefs_settings_repository.dart';

void main() async {
  // ── Phase 5: initialise persistent storage before runApp ──────────────────
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  // Open Hive boxes (adapters are registered inside each `open()` call).
  final weakItemRepo = await HiveWeakItemRepository.open();
  final planRepo = await HivePlanRepository.open();
  final reviewHistoryRepo = await HiveReviewHistoryRepository.open();
  final settingsRepo = SharedPreferencesSettingsRepository();

  runApp(
    ProviderScope(
      overrides: [
        weakItemRepoProvider.overrideWithValue(weakItemRepo),
        planRepoProvider.overrideWithValue(planRepo),
        reviewHistoryRepoProvider.overrideWithValue(reviewHistoryRepo),
        settingsRepoProvider.overrideWithValue(settingsRepo),
      ],
      child: const Tasmee3App(),
    ),
  );
}

class Tasmee3App extends StatelessWidget {
  const Tasmee3App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tasmee3 Trainer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
