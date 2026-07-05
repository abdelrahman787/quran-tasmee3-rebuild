/// JSON-based export/import for all Hive-backed review data.
///
/// Phase 7 — Production Polish.  Exports weak items, review plans, and review
/// history to a single JSON string that can be shared or saved by the user.
/// Import restores the data into the Hive boxes, replacing existing entries.
library;

import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:quran_tasmee3_core/review/models.dart';

/// Serialise all review data to a JSON string.
///
/// Returns a compact JSON string with keys: `version`, `exportedAt`,
/// `weakItems`, `plans`, `reviewHistory`.
Future<String> exportReviewData({
  required Box<WeakItem> weakItemBox,
  required Box<ReviewPlan> planBox,
  required Box<ReviewResult> historyBox,
}) async {
  final weakItems = <Map<String, dynamic>>[];
  for (final item in weakItemBox.values) {
    weakItems.add({
      'wordId': item.wordId,
      'surah': item.surah,
      'ayah': item.ayah,
      'wordIndex': item.wordIndex,
      'errorCount': item.errorCount,
      'lastErrorAt': item.lastErrorAt,
      'masteryScore': item.masteryScore,
      'forgetCount': item.forgetCount,
    });
  }

  final plans = <Map<String, dynamic>>[];
  for (final plan in planBox.values) {
    plans.add({
      'id': plan.id,
      'name': plan.name,
      'dailyTarget': plan.dailyTarget,
      'createdAt': plan.createdAt,
      'updatedAt': plan.updatedAt,
      'items': plan.items.map((item) => {
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
          }).toList(),
    });
  }

  final history = <Map<String, dynamic>>[];
  for (final result in historyBox.values) {
    history.add({
      'planItemId': result.planItemId,
      'score': result.score,
      'confirmedErrors': result.confirmedErrors,
      'totalWords': result.totalWords,
      'reviewedAt': result.reviewedAt,
    });
  }

  final export = {
    'version': 1,
    'exportedAt': DateTime.now().millisecondsSinceEpoch,
    'weakItems': weakItems,
    'plans': plans,
    'reviewHistory': history,
  };

  return const JsonEncoder.withIndent('  ').convert(export);
}

/// Import review data from a JSON string, replacing all existing entries.
///
/// Returns a summary string: `"imported: X weak items, Y plans, Z results"`.
Future<String> importReviewData({
  required String jsonString,
  required Box<WeakItem> weakItemBox,
  required Box<ReviewPlan> planBox,
  required Box<ReviewResult> historyBox,
}) async {
  final data = json.decode(jsonString) as Map<String, dynamic>;

  // Clear existing data.
  await weakItemBox.clear();
  await planBox.clear();
  await historyBox.clear();

  // Import weak items.
  final weakItems = data['weakItems'] as List? ?? [];
  for (final entry in weakItems) {
    final m = entry as Map<String, dynamic>;
    final item = WeakItem(
      wordId: m['wordId'] as String,
      surah: m['surah'] as int,
      ayah: m['ayah'] as int,
      wordIndex: m['wordIndex'] as int,
      errorCount: m['errorCount'] as int,
      lastErrorAt: m['lastErrorAt'] as int,
      masteryScore: (m['masteryScore'] as num).toDouble(),
      forgetCount: m['forgetCount'] as int? ?? 0,
    );
    await weakItemBox.put(item.wordId, item);
  }

  // Import plans.
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
    final plan = ReviewPlan(
      id: m['id'] as String,
      name: m['name'] as String,
      items: items,
      dailyTarget: m['dailyTarget'] as int,
      createdAt: m['createdAt'] as int,
      updatedAt: m['updatedAt'] as int,
    );
    await planBox.put(plan.id, plan);
  }

  // Import review history.
  final history = data['reviewHistory'] as List? ?? [];
  for (final entry in history) {
    final m = entry as Map<String, dynamic>;
    final result = ReviewResult(
      planItemId: m['planItemId'] as String,
      score: (m['score'] as num).toDouble(),
      confirmedErrors: m['confirmedErrors'] as int,
      totalWords: m['totalWords'] as int,
      reviewedAt: m['reviewedAt'] as int,
    );
    await historyBox.add(result);
  }

  return 'imported: ${weakItems.length} weak items, ${plans.length} plans, ${history.length} results';
}
