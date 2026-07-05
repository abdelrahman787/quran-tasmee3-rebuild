/// SharedPreferences-backed persistent [SettingsRepository].
///
/// Phase 5 — Persistent Storage.  User settings (daily target, recitation
/// mode, weakness threshold, mastery horizon, merge-contiguous flag) are
/// persisted as primitive key-value pairs in SharedPreferences.
///
/// On first launch (or after clearing prefs) [get] returns [UserSettings.defaults],
/// matching the in-memory behaviour.
library;

import 'package:quran_tasmee3_core/recitation/recitation_config.dart';
import 'package:quran_tasmee3_core/review/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesSettingsRepository implements SettingsRepository {
  static const _keyDailyTarget = 'settings_dailyTarget';
  static const _keyDefaultMode = 'settings_defaultMode';
  static const _keyWeaknessThreshold = 'settings_weaknessThreshold';
  static const _keyMasteryHorizonDays = 'settings_masteryHorizonDays';
  static const _keyMergeContiguous = 'settings_mergeContiguous';

  SharedPreferences? _prefs;

  /// Load (or reload) the underlying [SharedPreferences] instance.
  Future<void> _ensureLoaded() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<UserSettings> get() async {
    await _ensureLoaded();
    final p = _prefs!;

    // If no key has been written yet, return defaults (first-launch behaviour).
    final hasData = p.containsKey(_keyDailyTarget);
    if (!hasData) return UserSettings.defaults;

    return UserSettings(
      dailyTarget: p.getInt(_keyDailyTarget) ??
          UserSettings.defaults.dailyTarget,
      defaultMode: _modeFromWire(
          p.getString(_keyDefaultMode) ?? 'normal'),
      weaknessThreshold:
          p.getDouble(_keyWeaknessThreshold) ??
              UserSettings.defaults.weaknessThreshold,
      masteryHorizonDays: p.getInt(_keyMasteryHorizonDays) ??
          UserSettings.defaults.masteryHorizonDays,
      mergeContiguous: p.getBool(_keyMergeContiguous) ??
          UserSettings.defaults.mergeContiguous,
    );
  }

  @override
  Future<void> save(UserSettings settings) async {
    await _ensureLoaded();
    final p = _prefs!;

    await p.setInt(_keyDailyTarget, settings.dailyTarget);
    await p.setString(_keyDefaultMode, settings.defaultMode.name);
    await p.setDouble(_keyWeaknessThreshold, settings.weaknessThreshold);
    await p.setInt(_keyMasteryHorizonDays, settings.masteryHorizonDays);
    await p.setBool(_keyMergeContiguous, settings.mergeContiguous);
  }

  /// Convert a stored mode string back to the enum.
  static RecitationMode _modeFromWire(String s) {
    switch (s) {
      case 'easy':
        return RecitationMode.easy;
      case 'strict':
        return RecitationMode.strict;
      default:
        return RecitationMode.normal;
    }
  }
}
