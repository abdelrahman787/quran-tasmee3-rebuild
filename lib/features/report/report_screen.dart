/// Report screen — post-session report showing the student's performance.
///
/// Displays:
///  - Overall score (1 - confirmedErrors / totalWords)
///  - Error breakdown by category (forget, substitution, order, addition, pronunciation, asrLag)
///  - Per-ayah accuracy
///  - Detailed error list with expected vs recognized text
///
/// Built from [SessionReport] (pure Dart, from the core package).
library;

import 'package:flutter/material.dart';
import 'package:quran_tasmee3_core/recitation/matching_engine.dart';
import 'package:quran_tasmee3_core/recitation/session_report.dart';

import '../../app/app_theme.dart';
import '../../models/quran_data.dart';

class ReportScreen extends StatelessWidget {
  final SessionReport report;

  const ReportScreen({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تقرير الجلسة'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ScoreCard(report: report),
            const SizedBox(height: 16),
            _ErrorBreakdownCard(report: report),
            const SizedBox(height: 16),
            _PerAyahCard(report: report),
            const SizedBox(height: 16),
            if (report.substitutions.isNotEmpty ||
                report.orderErrors.isNotEmpty ||
                report.forgetCount > 0)
              _ErrorListCard(report: report),
            const SizedBox(height: 24),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('عودة'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.popUntil(context, (route) => route.isFirst);
                    },
                    icon: const Icon(Icons.home),
                    label: const Text('الرئيسية'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final SessionReport report;

  const _ScoreCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final scorePercent = (report.score * 100).round();
    final scoreColor = scorePercent >= 80
        ? AppTheme.primaryGreen
        : scorePercent >= 60
            ? AppTheme.goldAccent
            : AppTheme.wordError;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text(
              'النتيجة',
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.inkMedium,
              ),
            ),
            const SizedBox(height: 12),
            // Score circle
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: scoreColor, width: 4),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$scorePercent%',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: scoreColor,
                      ),
                    ),
                    Text(
                      '${report.confirmedErrors} خطأ',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatItem(
                  label: 'الكلمات',
                  value: '${report.totalWords}',
                ),
                _StatItem(
                  label: 'أخطاء مؤكدة',
                  value: '${report.confirmedErrors}',
                  color: AppTheme.wordError,
                ),
                _StatItem(
                  label: 'أخطاء بسيطة',
                  value: '${report.softErrors}',
                  color: AppTheme.wordSoftError,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _StatItem({
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color ?? AppTheme.inkDark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

class _ErrorBreakdownCard extends StatelessWidget {
  final SessionReport report;

  const _ErrorBreakdownCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final categories = <_ErrorCategory>[
      _ErrorCategory(
        icon: Icons.visibility_off,
        label: 'نسيان (صمت)',
        count: report.forgetSilence.length,
        color: AppTheme.wordError,
      ),
      _ErrorCategory(
        icon: Icons.touch_app,
        label: 'نسيان (كشف يدوي)',
        count: report.forgetManual.length,
        color: AppTheme.wordSoftError,
      ),
      _ErrorCategory(
        icon: Icons.swap_horiz,
        label: 'استبدال',
        count: report.substitutions.length,
        color: AppTheme.wordError,
      ),
      _ErrorCategory(
        icon: Icons.add,
        label: 'زيادة',
        count: report.additions.length,
        color: AppTheme.wordSoftError,
      ),
      _ErrorCategory(
        icon: Icons.sort,
        label: 'خطأ ترتيب',
        count: report.orderErrors.length,
        color: AppTheme.wordSoftError,
      ),
      _ErrorCategory(
        icon: Icons.record_voice_over,
        label: 'نطق',
        count: report.pronunciations.length,
        color: AppTheme.wordPronunciation,
      ),
      _ErrorCategory(
        icon: Icons.schedule,
        label: 'تأخر تعرف',
        count: report.asrLag.length,
        color: Colors.grey,
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'تفصيل الأخطاء',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.inkDark,
              ),
            ),
            const SizedBox(height: 12),
            ...categories.map((cat) {
              if (cat.count == 0) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(cat.icon, color: cat.color, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        cat.label,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: cat.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${cat.count}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: cat.color,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (categories.every((c) => c.count == 0))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'لا توجد أخطاء — أحسنت!',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppTheme.primaryGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCategory {
  final IconData icon;
  final String label;
  final int count;
  final Color color;

  const _ErrorCategory({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });
}

class _PerAyahCard extends StatelessWidget {
  final SessionReport report;

  const _PerAyahCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'دقة كل آية',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.inkDark,
              ),
            ),
            const SizedBox(height: 12),
            ...report.perAyah.map((ayah) {
              final surah = QuranData.getSurah(ayah.surah);
              final accuracyPercent = (ayah.accuracy * 100).round();
              final accColor = accuracyPercent >= 80
                  ? AppTheme.primaryGreen
                  : accuracyPercent >= 60
                      ? AppTheme.goldAccent
                      : AppTheme.wordError;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${surah?.name ?? ''} ${ayah.ayah}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$accuracyPercent% (${ayah.errorWords}/${ayah.totalWords})',
                          style: TextStyle(
                            fontSize: 13,
                            color: accColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ayah.accuracy,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation(accColor),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _ErrorListCard extends StatelessWidget {
  final SessionReport report;

  const _ErrorListCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final allErrors = <ReportEntry>[
      ...report.forgetSilence,
      ...report.forgetManual,
      ...report.substitutions,
      ...report.additions,
      ...report.orderErrors,
      ...report.pronunciations,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'قائمة الأخطاء',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.inkDark,
              ),
            ),
            const SizedBox(height: 12),
            ...allErrors.map((entry) {
              final surah = QuranData.getSurah(entry.surah);
              final typeLabel = _errorTypeLabel(entry.errorType);
              final typeColor = _errorTypeColor(entry.errorType);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: typeColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: typeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              typeLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: typeColor,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${surah?.name ?? ''} ${entry.surah}:${entry.ayah}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text(
                            'المتوقع: ',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.inkMedium,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              entry.expectedText,
                              style: const TextStyle(
                                fontSize: 16,
                                fontFamily: 'Amiri',
                                color: AppTheme.wordRevealed,
                              ),
                              textDirection: TextDirection.rtl,
                            ),
                          ),
                        ],
                      ),
                      if (entry.recognizedText != null &&
                          entry.recognizedText!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Text(
                              'المتلفظ: ',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.inkMedium,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                entry.recognizedText!,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontFamily: 'Amiri',
                                  color: AppTheme.wordError,
                                  decoration: TextDecoration.lineThrough,
                                ),
                                textDirection: TextDirection.rtl,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _errorTypeLabel(ErrorType type) {
    return switch (type) {
      ErrorType.forget => 'نسيان',
      ErrorType.substitution => 'استبدال',
      ErrorType.order => 'ترتيب',
      ErrorType.pronunciation => 'نطق',
      ErrorType.addition => 'زيادة',
      ErrorType.asrLag => 'تأخر تعرف',
    };
  }

  Color _errorTypeColor(ErrorType type) {
    return switch (type) {
      ErrorType.forget => AppTheme.wordError,
      ErrorType.substitution => AppTheme.wordError,
      ErrorType.order => AppTheme.wordSoftError,
      ErrorType.pronunciation => AppTheme.wordPronunciation,
      ErrorType.addition => AppTheme.wordSoftError,
      ErrorType.asrLag => Colors.grey,
    };
  }
}
