/// Tests for Hive-backed persistent repositories (Phase 5).
///
/// These tests verify that the Hive repositories correctly implement the
/// core interfaces and that data round-trips through Hive storage.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:quran_tasmee3_core/review/models.dart';

import 'package:tasmee3_trainer/services/persistence/hive_adapters.dart';
import 'package:tasmee3_trainer/services/persistence/hive_repositories.dart';

void main() {
  setUpAll(() {
    // Use a temporary directory-backed Hive for tests.
    Hive.init(Directory.systemTemp.createTempSync('hive_test_').path);
    registerHiveAdapters();
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
  });

  group('HiveWeakItemRepository', () {
    late HiveWeakItemRepository repo;

    setUp(() async {
      repo = await HiveWeakItemRepository.open();
      await repo.clear();
    });

    test('upsert and get', () async {
      final item = WeakItem(
        wordId: '1:1:0',
        surah: 1,
        ayah: 1,
        wordIndex: 0,
        errorCount: 2,
        lastErrorAt: 1700000000000,
        masteryScore: 0.5,
      );
      await repo.upsert(item);

      final got = await repo.get('1:1:0');
      expect(got, isNotNull);
      expect(got!.wordId, '1:1:0');
      expect(got.surah, 1);
      expect(got.errorCount, 2);
      expect(got.masteryScore, 0.5);
    });

    test('getAll returns all items', () async {
      await repo.upsert(WeakItem(
        wordId: '1:1:0', surah: 1, ayah: 1, wordIndex: 0,
        errorCount: 1, lastErrorAt: 0, masteryScore: 0.8,
      ));
      await repo.upsert(WeakItem(
        wordId: '1:1:1', surah: 1, ayah: 1, wordIndex: 1,
        errorCount: 3, lastErrorAt: 0, masteryScore: 0.4,
      ));

      final all = await repo.getAll();
      expect(all.length, 2);
    });

    test('getMany returns only existing items', () async {
      await repo.upsert(WeakItem(
        wordId: '1:1:0', surah: 1, ayah: 1, wordIndex: 0,
        errorCount: 1, lastErrorAt: 0, masteryScore: 0.8,
      ));

      final many = await repo.getMany(['1:1:0', '99:99:99']);
      expect(many.length, 1);
      expect(many.containsKey('1:1:0'), isTrue);
    });

    test('upsertAll batches writes', () async {
      await repo.upsertAll([
        WeakItem(wordId: '1:1:0', surah: 1, ayah: 1, wordIndex: 0,
            errorCount: 1, lastErrorAt: 0, masteryScore: 0.8),
        WeakItem(wordId: '1:1:1', surah: 1, ayah: 1, wordIndex: 1,
            errorCount: 2, lastErrorAt: 0, masteryScore: 0.6),
        WeakItem(wordId: '2:1:0', surah: 2, ayah: 1, wordIndex: 0,
            errorCount: 1, lastErrorAt: 0, masteryScore: 0.9),
      ]);

      expect((await repo.getAll()).length, 3);
    });

    test('delete removes item', () async {
      await repo.upsert(WeakItem(
        wordId: '1:1:0', surah: 1, ayah: 1, wordIndex: 0,
        errorCount: 1, lastErrorAt: 0, masteryScore: 0.8,
      ));
      await repo.delete('1:1:0');
      expect(await repo.get('1:1:0'), isNull);
    });

    test('clear empties the box', () async {
      await repo.upsert(WeakItem(
        wordId: '1:1:0', surah: 1, ayah: 1, wordIndex: 0,
        errorCount: 1, lastErrorAt: 0, masteryScore: 0.8,
      ));
      await repo.clear();
      expect((await repo.getAll()).length, 0);
    });

    test('forgetCount defaults to 0', () async {
      await repo.upsert(WeakItem(
        wordId: '1:1:0', surah: 1, ayah: 1, wordIndex: 0,
        errorCount: 1, lastErrorAt: 0, masteryScore: 0.8,
      ));
      final got = await repo.get('1:1:0');
      expect(got!.forgetCount, 0);
    });
  });

  group('HivePlanRepository', () {
    late HivePlanRepository repo;

    setUp(() async {
      repo = await HivePlanRepository.open();
      // Clear all plans
      final all = await repo.getAll();
      for (final p in all) {
        await repo.delete(p.id);
      }
    });

    test('save and get round-trips items', () async {
      final plan = ReviewPlan(
        id: 'plan_1',
        name: 'Daily Review',
        items: [
          PlanItem(id: 'item_1', surah: 1, ayah: 1, dueAt: 1700000000000),
          PlanItem(id: 'item_2', surah: 1, ayah: 2,
              ayahEnd: 4, dueAt: 1700000000000,
              status: PlanItemStatus.due),
        ],
        dailyTarget: 10,
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
      );
      await repo.save(plan);

      final got = await repo.get('plan_1');
      expect(got, isNotNull);
      expect(got!.name, 'Daily Review');
      expect(got.items.length, 2);
      expect(got.items[0].surah, 1);
      expect(got.items[1].isRange, isTrue);
      expect(got.items[1].ayahEnd, 4);
      expect(got.items[1].status, PlanItemStatus.due);
    });

    test('getAll returns all plans', () async {
      await repo.save(ReviewPlan(
        id: 'p1', name: 'A', items: [], dailyTarget: 5,
        createdAt: 0, updatedAt: 0,
      ));
      await repo.save(ReviewPlan(
        id: 'p2', name: 'B', items: [], dailyTarget: 10,
        createdAt: 0, updatedAt: 0,
      ));
      final all = await repo.getAll();
      expect(all.length, 2);
    });

    test('delete removes plan', () async {
      await repo.save(ReviewPlan(
        id: 'p1', name: 'A', items: [], dailyTarget: 5,
        createdAt: 0, updatedAt: 0,
      ));
      await repo.delete('p1');
      expect(await repo.get('p1'), isNull);
    });
  });

  group('HiveReviewHistoryRepository', () {
    late HiveReviewHistoryRepository repo;

    setUp(() async {
      repo = await HiveReviewHistoryRepository.open();
      // Clear all history entries (box is already open from open()).
      await Hive.box<ReviewResult>('reviewHistory').clear();
    });

    test('add and getAll', () async {
      await repo.add(ReviewResult(
        planItemId: 'item_1', score: 0.85, confirmedErrors: 2,
        totalWords: 10, reviewedAt: 1700000000000,
      ));
      await repo.add(ReviewResult(
        planItemId: 'item_2', score: 1.0, confirmedErrors: 0,
        totalWords: 5, reviewedAt: 1700000000001,
      ));

      final all = await repo.getAll();
      expect(all.length, 2);
    });

    test('forItem filters by planItemId', () async {
      await repo.add(ReviewResult(
        planItemId: 'item_1', score: 0.85, confirmedErrors: 2,
        totalWords: 10, reviewedAt: 1700000000000,
      ));
      await repo.add(ReviewResult(
        planItemId: 'item_2', score: 1.0, confirmedErrors: 0,
        totalWords: 5, reviewedAt: 1700000000001,
      ));
      await repo.add(ReviewResult(
        planItemId: 'item_1', score: 0.5, confirmedErrors: 5,
        totalWords: 10, reviewedAt: 1700000000002,
      ));

      final forItem1 = await repo.forItem('item_1');
      expect(forItem1.length, 2);
      for (final r in forItem1) {
        expect(r.planItemId, 'item_1');
      }
    });
  });
}
