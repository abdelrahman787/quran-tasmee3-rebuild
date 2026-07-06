/// JSON-based export/import for all Hive-backed review data.
///
/// Phase 7 — Production Polish.  Exports weak items, review plans, and review
/// history to a single JSON string that can be shared or saved by the user.
/// Import restores the data via the repository interfaces, replacing existing
/// weak items and plans, and appending review history.
///
/// This is the **single implementation** of export/import logic — the settings
/// screen calls these functions rather than duplicating the serialization.
library;

import 'dart:convert';

import 'package:quran_tasmee3_core/review/models.dart';
import 'package:quran_tasmee3_core/review/repositories.dart';

/// Serialise all review data to a JSON string.
///
/// Returns a compact JSON string with keys: `version`, `exportedAt`,
/// `weakItems`, `plans`, `reviewHistory`.
///
/// Reads data through the repository interfaces so it works with any
/// backing store (Hive, in-memory, Firestore).
Future<String> exportReviewData({
  required WeakItemRepository weakItemRepo,
  required PlanRepository planRepo,
  required ReviewHistoryRepository historyRepo,
}) async {
  final weakItems = await weakItemRepo.getAll();
  final plans = await planRepo.getAll();
  final history = await historyRepo.getAll();

  final export = <String, dynamic>{
    'version': 1,
    'exportedAt': DateTime.now().millisecondsSinceEpoch,
    'weakItems': weakItems
        .map((item) => {
              'wordId': item.wordId,
              'surah': item.surah,
              'ayah': item.ayah,
              'wordIndex': item.wordIndex,
              'errorCount': item.errorCount,
              'lastErrorAt': item.lastErrorAt,
              'masteryScore': item.masteryScore,
              'forgetCount': item.forgetCount,
            })
        .toList(),
    'plans': plans
        .map((plan) => {
              'id': plan.id,
              'name': plan.name,
              'dailyTarget': plan.dailyTarget,
              'createdAt': plan.createdAt,
              'updatedAt': plan.updatedAt,
              'items': plan.items
                  .map((item) => {
                        'id': item.id,
                        'surah': item.surah,
                        'ayah': item.ayah,
                        'ayahEnd': item.ayahEnd,
                        'ease': item.ease,
                        'intervalDays': item.intervalDays,
                        'repetitions': item.repetitions,
                        'dueAt': item.dueAt,
                        'lastScore': item.lastScore,
                        'status': item.status.wire,
                      })
                  .toList(),
            })
        .toList(),
    'reviewHistory': history
        .map((r) => {
              'planItemId': r.planItemId,
              'score': r.score,
              'confirmedErrors': r.confirmedErrors,
              'totalWords': r.totalWords,
              'reviewedAt': r.reviewedAt,
            })
        .toList(),
  };

  return const JsonEncoder.withIndent('  ').convert(export);
}

/// Import review data from a JSON string, replacing existing entries.
///
/// - Weak items: cleared then re-imported via [WeakItemRepository.upsert].
/// - Plans: existing plans deleted, then imported plans saved.
/// - Review history: appended via [ReviewHistoryRepository.add] (the interface
///   is append-only by design — no `clear()` method).
///
/// Returns a summary string: `"imported: X weak items, Y plans, Z results"`.
///
/// Throws [FormatException] if the JSON is invalid.
Future<String> importReviewData({
  required String jsonString,
  required WeakItemRepository weakItemRepo,
  required PlanRepository planRepo,
  required ReviewHistoryRepository historyRepo,
}) async {
  final data = json.decode(jsonString) as Map<String, dynamic>;

  // ── Clear and re-import weak items ──────────────────────────────────────
  await weakItemRepo.clear();

  final weakItems = data['weakItems'] as List? ?? [];
  for (final entry in weakItems) {
    final m = entry as Map<String, dynamic>;
    await weakItemRepo.upsert(WeakItem(
      wordId: m['wordId'] as String,
      surah: m['surah'] as int,
      ayah: m['ayah'] as int,
      wordIndex: m['wordIndex'] as int,
      errorCount: m['errorCount'] as int,
      lastErrorAt: m['lastErrorAt'] as int,
      masteryScore: (m['masteryScore'] as num).toDouble(),
      forgetCount: m['forgetCount'] as int? ?? 0,
    ));
  }

  // ── Clear and re-import plans ───────────────────────────────────────────
  final existingPlans = await planRepo.getAll();
  for (final p in existingPlans) {
    await planRepo.delete(p.id);
  }

  final plans = data['plans'] as List? ?? [];
  for (final entry in plans) {
    final m = entry as Map<String, dynamic>;
    final items = (m['items'] as List? ?? []).map((e) {
      final im = e as Map<String, dynamic>;
      return PlanItem(
        id: im['id'] as String,
        surah: im['surah'] as int,
        ayah: im['ayah'] as int,
        ayahEnd: im['ayahEnd'] as int?,
        ease: (im['ease'] as num).toDouble(),
        intervalDays: im['intervalDays'] as int,
        repetitions: im['repetitions'] as int,
        dueAt: im['dueAt'] as int,
        lastScore: im['lastScore'] != null
            ? (im['lastScore'] as num).toDouble()
            : null,
        status: PlanItemStatusWire.fromWire(im['status'] as String),
      );
    }).toList();
    await planRepo.save(ReviewPlan(
      id: m['id'] as String,
      name: m['name'] as String,
      items: items,
      dailyTarget: m['dailyTarget'] as int,
      createdAt: m['createdAt'] as int,
      updatedAt: m['updatedAt'] as int,
    ));
  }

  // ── Append review history (interface is append-only — no clear) ─────────
  final history = data['reviewHistory'] as List? ?? [];
  for (final entry in history) {
    final m = entry as Map<String, dynamic>;
    await historyRepo.add(ReviewResult(
      planItemId: m['planItemId'] as String,
      score: (m['score'] as num).toDouble(),
      confirmedErrors: m['confirmedErrors'] as int,
      totalWords: m['totalWords'] as int,
      reviewedAt: m['reviewedAt'] as int,
    ));
  }

  return 'imported: ${weakItems.length} weak items, ${plans.length} plans, ${history.length} results';
}
