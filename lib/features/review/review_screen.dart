/// Review screen — SM-2 spaced repetition review plan.
///
/// Shows:
///  - Today's review queue (due items)
///  - Upcoming reviews
///  - Plan statistics
///  - Weak items overview
///
/// Uses the core package's scheduler and review service.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quran_tasmee3_core/review/models.dart';
import 'package:quran_tasmee3_core/review/review_service.dart';
import 'package:quran_tasmee3_core/review/scheduler.dart';

import '../../app/app_theme.dart';
import '../../app/providers.dart';
import '../../models/quran_data.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  ReviewPlan? _autoPlan;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPlan());
  }

  Future<void> _loadPlan() async {
    final weakItems = ref.read(weakItemRepoProvider);
    final plans = ref.read(planRepoProvider);
    final history = ref.read(reviewHistoryRepoProvider);
    final clock = ref.read(clockProvider);

    final service = ReviewService(
      weakItems: weakItems,
      plans: plans,
      history: history,
    );

    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      final plan = await service.rebuildAutoPlan(nowMs: clock());
      if (mounted) {
        setState(() {
          _autoPlan = plan;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مراجعة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPlan,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : _autoPlan == null
                  ? _buildEmptyState()
                  : _buildPlanContent(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            const Text(
              'حدث خطأ أثناء تحميل خطة المراجعة',
              style: TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadPlan,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.school,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'لا توجد خطة مراجعة',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'أكمل جلسات تسميع لإنشاء خطة مراجعة',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanContent() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final plan = _autoPlan!;
    final dueItems = dueToday(plan, now);
    final upcomingItems = upcoming(plan, now);
    final queue = todaysQueue(plan, now);
    final masteredCount = plan.items
        .where((i) => i.status == PlanItemStatus.mastered)
        .length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Plan summary card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'خطة المراجعة',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.inkDark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _SummaryStat(
                        label: 'المستحقة اليوم',
                        value: '${dueItems.length}',
                        color: AppTheme.wordError,
                      ),
                      _SummaryStat(
                        label: 'القادمة',
                        value: '${upcomingItems.length}',
                        color: AppTheme.primaryGreen,
                      ),
                      _SummaryStat(
                        label: 'متقنة',
                        value: '$masteredCount',
                        color: AppTheme.goldAccent,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Today's queue
          if (queue.isNotEmpty) ...[
            const _SectionHeader(title: 'قائمة اليوم', icon: Icons.today),
            const SizedBox(height: 8),
            ...queue.map((item) => _PlanItemTile(
                  item: item,
                  isDue: true,
                )),
            const SizedBox(height: 16),
          ],
          // Upcoming
          if (upcomingItems.isNotEmpty) ...[
            const _SectionHeader(title: 'القادمة', icon: Icons.schedule),
            const SizedBox(height: 8),
            ...upcomingItems.take(10).map((item) => _PlanItemTile(
                  item: item,
                  isDue: false,
                )),
          ],
          if (plan.items.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'لا توجد عناصر للمراجعة.\nأكمل جلسة تسميع لإنشاء عناصر المراجعة.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryGreen, size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.inkDark,
          ),
        ),
      ],
    );
  }
}

class _PlanItemTile extends StatelessWidget {
  final PlanItem item;
  final bool isDue;

  const _PlanItemTile({required this.item, required this.isDue});

  @override
  Widget build(BuildContext context) {
    final surah = QuranData.getSurah(item.surah);
    final dueDate = DateTime.fromMillisecondsSinceEpoch(item.dueAt);
    final now = DateTime.now();
    final daysUntil = dueDate.difference(now).inDays;

    String dueLabel;
    Color dueColor;
    if (isDue) {
      dueLabel = 'مستحقة الآن';
      dueColor = AppTheme.wordError;
    } else if (daysUntil == 0) {
      dueLabel = 'اليوم';
      dueColor = AppTheme.goldAccent;
    } else if (daysUntil == 1) {
      dueLabel = 'غداً';
      dueColor = AppTheme.primaryGreen;
    } else {
      dueLabel = 'بعد $daysUntil يوم';
      dueColor = Colors.grey;
    }

    final statusLabel = switch (item.status) {
      PlanItemStatus.newItem => 'جديد',
      PlanItemStatus.due => 'مستحق',
      PlanItemStatus.scheduled => 'مجدول',
      PlanItemStatus.mastered => 'متقن',
    };

    final statusColor = switch (item.status) {
      PlanItemStatus.newItem => Colors.blue,
      PlanItemStatus.due => AppTheme.wordError,
      PlanItemStatus.scheduled => AppTheme.primaryGreen,
      PlanItemStatus.mastered => AppTheme.goldAccent,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: statusColor.withValues(alpha: 0.12),
          ),
          child: Center(
            child: Text(
              '${item.surah}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ),
        ),
        title: Text(
          '${surah?.name ?? ''} ${item.ayah}${item.isRange ? '-${item.ayahEnd}' : ''}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              dueLabel,
              style: TextStyle(
                fontSize: 12,
                color: dueColor,
              ),
            ),
          ],
        ),
        trailing: item.lastScore != null
            ? Text(
                '${(item.lastScore! * 100).round()}%',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryGreen,
                ),
              )
            : null,
      ),
    );
  }
}
