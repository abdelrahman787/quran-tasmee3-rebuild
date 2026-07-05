/// Manual Hive TypeAdapters for core review models.
///
/// The `quran_tasmee3_core` package is pure-Dart and read-only (never modify),
/// so its models (`WeakItem`, `PlanItem`, `ReviewPlan`, `ReviewResult`) cannot
/// carry `@HiveType` annotations.  Instead we register hand-written adapters
/// that serialise to / from plain `Map<String, dynamic>` which Hive stores
/// natively.
///
/// Adapters are registered once at startup via [registerHiveAdapters].
library;

import 'package:hive/hive.dart';
import 'package:quran_tasmee3_core/review/models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WeakItem
// ─────────────────────────────────────────────────────────────────────────────

class WeakItemAdapter extends TypeAdapter<WeakItem> {
  @override
  final int typeId = 11;

  @override
  WeakItem read(BinaryReader reader) {
    final map = reader.readMap().cast<String, dynamic>();
    return WeakItem(
      wordId: map['wordId'] as String,
      surah: map['surah'] as int,
      ayah: map['ayah'] as int,
      wordIndex: map['wordIndex'] as int,
      errorCount: map['errorCount'] as int,
      lastErrorAt: map['lastErrorAt'] as int,
      masteryScore: (map['masteryScore'] as num).toDouble(),
      forgetCount: map['forgetCount'] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, WeakItem obj) {
    writer.writeMap({
      'wordId': obj.wordId,
      'surah': obj.surah,
      'ayah': obj.ayah,
      'wordIndex': obj.wordIndex,
      'errorCount': obj.errorCount,
      'lastErrorAt': obj.lastErrorAt,
      'masteryScore': obj.masteryScore,
      'forgetCount': obj.forgetCount,
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PlanItem
// ─────────────────────────────────────────────────────────────────────────────

class PlanItemAdapter extends TypeAdapter<PlanItem> {
  @override
  final int typeId = 12;

  @override
  PlanItem read(BinaryReader reader) {
    final map = reader.readMap().cast<String, dynamic>();
    return PlanItem(
      id: map['id'] as String,
      surah: map['surah'] as int,
      ayah: map['ayah'] as int,
      ayahEnd: map['ayahEnd'] as int?,
      ease: (map['ease'] as num).toDouble(),
      intervalDays: map['intervalDays'] as int,
      repetitions: map['repetitions'] as int,
      dueAt: map['dueAt'] as int,
      lastScore: map['lastScore'] != null
          ? (map['lastScore'] as num).toDouble()
          : null,
      status: PlanItemStatusWire.fromWire(map['status'] as String),
    );
  }

  @override
  void write(BinaryWriter writer, PlanItem obj) {
    writer.writeMap({
      'id': obj.id,
      'surah': obj.surah,
      'ayah': obj.ayah,
      'ayahEnd': obj.ayahEnd,
      'ease': obj.ease,
      'intervalDays': obj.intervalDays,
      'repetitions': obj.repetitions,
      'dueAt': obj.dueAt,
      'lastScore': obj.lastScore,
      'status': obj.status.wire,
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ReviewPlan
// ─────────────────────────────────────────────────────────────────────────────

class ReviewPlanAdapter extends TypeAdapter<ReviewPlan> {
  @override
  final int typeId = 13;

  @override
  ReviewPlan read(BinaryReader reader) {
    final map = reader.readMap().cast<String, dynamic>();
    // Hive automatically deserialises list elements using registered adapters.
    final items = (map['items'] as List).cast<PlanItem>();
    return ReviewPlan(
      id: map['id'] as String,
      name: map['name'] as String,
      items: items,
      dailyTarget: map['dailyTarget'] as int,
      createdAt: map['createdAt'] as int,
      updatedAt: map['updatedAt'] as int,
    );
  }

  @override
  void write(BinaryWriter writer, ReviewPlan obj) {
    writer.writeMap({
      'id': obj.id,
      'name': obj.name,
      'items': obj.items, // Hive uses registered PlanItemAdapter
      'dailyTarget': obj.dailyTarget,
      'createdAt': obj.createdAt,
      'updatedAt': obj.updatedAt,
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ReviewResult
// ─────────────────────────────────────────────────────────────────────────────

class ReviewResultAdapter extends TypeAdapter<ReviewResult> {
  @override
  final int typeId = 14;

  @override
  ReviewResult read(BinaryReader reader) {
    final map = reader.readMap().cast<String, dynamic>();
    return ReviewResult(
      planItemId: map['planItemId'] as String,
      score: (map['score'] as num).toDouble(),
      confirmedErrors: map['confirmedErrors'] as int,
      totalWords: map['totalWords'] as int,
      reviewedAt: map['reviewedAt'] as int,
    );
  }

  @override
  void write(BinaryWriter writer, ReviewResult obj) {
    writer.writeMap({
      'planItemId': obj.planItemId,
      'score': obj.score,
      'confirmedErrors': obj.confirmedErrors,
      'totalWords': obj.totalWords,
      'reviewedAt': obj.reviewedAt,
    });
  }
}

/// Register all Hive adapters.  Call once before opening any box.
void registerHiveAdapters() {
  // Guard against double registration.
  if (Hive.isAdapterRegistered(11)) return;
  Hive.registerAdapter(WeakItemAdapter());
  Hive.registerAdapter(PlanItemAdapter());
  Hive.registerAdapter(ReviewPlanAdapter());
  Hive.registerAdapter(ReviewResultAdapter());
}
