/// Hive-backed persistent implementations of the core review repositories.
///
/// Phase 5 — Persistent Storage.  These replace the in-memory implementations
/// from `quran_tasmee3_core/review/repositories.dart` with Hive box storage,
/// so weak items, review plans, and review history survive app restarts.
///
/// Boxes must be opened **before** the provider is read.  In `main()` we call
/// `await Hive.openBox(...)` for each, then pass the already-open box to the
/// provider.
library;

import 'package:hive/hive.dart';
import 'package:quran_tasmee3_core/review/models.dart';
import 'package:quran_tasmee3_core/review/repositories.dart';

import 'hive_adapters.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// HiveWeakItemRepository
// ═══════════════════════════════════════════════════════════════════════════════

/// Persistent [WeakItemRepository] backed by a Hive box.
///
/// Keyed by `wordId` (`"<surah>:<ayah>:<wordIndex>"`).  Values are [WeakItem]
/// objects (registered via [WeakItemAdapter]).
class HiveWeakItemRepository implements WeakItemRepository {
  final Box<WeakItem> _box;

  HiveWeakItemRepository(this._box);

  /// Open the box and return a ready-to-use repository.
  /// Idempotent: returns the existing box if already open.
  static Future<HiveWeakItemRepository> open() async {
    registerHiveAdapters();
    final box = Hive.isBoxOpen('weakItems')
        ? Hive.box<WeakItem>('weakItems')
        : await Hive.openBox<WeakItem>('weakItems');
    return HiveWeakItemRepository(box);
  }

  @override
  Future<List<WeakItem>> getAll() async {
    return _box.values.toList();
  }

  @override
  Future<WeakItem?> get(String wordId) async {
    return _box.get(wordId);
  }

  @override
  Future<Map<String, WeakItem>> getMany(Iterable<String> wordIds) async {
    final result = <String, WeakItem>{};
    for (final id in wordIds) {
      final item = _box.get(id);
      if (item != null) result[id] = item;
    }
    return result;
  }

  @override
  Future<void> upsert(WeakItem item) async {
    await _box.put(item.wordId, item);
  }

  @override
  Future<void> upsertAll(Iterable<WeakItem> items) async {
    final map = <String, WeakItem>{};
    for (final it in items) {
      map[it.wordId] = it;
    }
    await _box.putAll(map);
  }

  @override
  Future<void> delete(String wordId) async {
    await _box.delete(wordId);
  }

  @override
  Future<void> clear() async {
    await _box.clear();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HivePlanRepository
// ═══════════════════════════════════════════════════════════════════════════════

/// Persistent [PlanRepository] backed by a Hive box.
///
/// Keyed by `planId`; values are [ReviewPlan] objects.
class HivePlanRepository implements PlanRepository {
  final Box<ReviewPlan> _box;

  HivePlanRepository(this._box);

  static Future<HivePlanRepository> open() async {
    registerHiveAdapters();
    final box = Hive.isBoxOpen('reviewPlans')
        ? Hive.box<ReviewPlan>('reviewPlans')
        : await Hive.openBox<ReviewPlan>('reviewPlans');
    return HivePlanRepository(box);
  }

  @override
  Future<List<ReviewPlan>> getAll() async {
    return _box.values.toList();
  }

  @override
  Future<ReviewPlan?> get(String planId) async {
    return _box.get(planId);
  }

  @override
  Future<void> save(ReviewPlan plan) async {
    await _box.put(plan.id, plan);
  }

  @override
  Future<void> delete(String planId) async {
    await _box.delete(planId);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HiveReviewHistoryRepository
// ═══════════════════════════════════════════════════════════════════════════════

/// Persistent [ReviewHistoryRepository] backed by a Hive box.
///
/// Append-only.  Each entry gets an auto-increment key so insertion order is
/// preserved; `forItem` does an in-memory filter (no index needed).
class HiveReviewHistoryRepository implements ReviewHistoryRepository {
  final Box<ReviewResult> _box;

  HiveReviewHistoryRepository(this._box);

  static Future<HiveReviewHistoryRepository> open() async {
    registerHiveAdapters();
    final box = Hive.isBoxOpen('reviewHistory')
        ? Hive.box<ReviewResult>('reviewHistory')
        : await Hive.openBox<ReviewResult>('reviewHistory');
    return HiveReviewHistoryRepository(box);
  }

  @override
  Future<void> add(ReviewResult result) async {
    await _box.add(result); // auto-increment key
  }

  @override
  Future<List<ReviewResult>> getAll() async {
    return _box.values.toList();
  }

  @override
  Future<List<ReviewResult>> forItem(String planItemId) async {
    return _box.values.where((r) => r.planItemId == planItemId).toList();
  }
}
