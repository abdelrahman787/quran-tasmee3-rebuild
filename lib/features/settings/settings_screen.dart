/// Settings screen — user preferences and app configuration.
///
/// Settings:
///  - Recitation mode (easy/normal/strict)
///  - Daily review target
///  - Weakness threshold
///  - Mastery horizon (days)
///  - Merge contiguous ayat toggle
///  - Data backup (export/import review data — delegated to data_backup.dart)
///  - About / version info
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quran_tasmee3_core/recitation/recitation_config.dart';
import 'package:quran_tasmee3_core/review/settings.dart';

import '../../app/app_theme.dart';
import '../../app/providers.dart';
import '../../services/persistence/data_backup.dart';

// Conditional import: real dev screen on mobile (dart:io), stub on web.
// Both files export DevAsrScreen with the same API.
import '../dev_asr/dev_asr_screen_stub.dart'
    if (dart.library.io) '../dev_asr/dev_asr_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  UserSettings? _settings;
  bool _isLoading = true;
  bool _isExporting = false;
  bool _isImporting = false;

  // Hidden dev screen access: tap version/about row 7 times within 3 seconds.
  // Uses plain onTap (not onLongPress) to avoid gesture-arena conflicts.
  // Follows Android's "Developer options" convention.
  int _versionTapCount = 0;
  DateTime? _firstVersionTapTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  Future<void> _loadSettings() async {
    final repo = ref.read(settingsRepoProvider);
    final s = await repo.get();
    if (mounted) {
      setState(() {
        _settings = s;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings(UserSettings settings) async {
    final repo = ref.read(settingsRepoProvider);
    await repo.save(settings);
    setState(() => _settings = settings);
  }

  void _onVersionTap() {
    final now = DateTime.now();

    // Reset count if more than 3 seconds since first tap.
    if (_firstVersionTapTime != null &&
        now.difference(_firstVersionTapTime!).inSeconds > 3) {
      _versionTapCount = 0;
    }

    if (_versionTapCount == 0) {
      _firstVersionTapTime = now;
    }

    _versionTapCount++;

    if (_versionTapCount >= 7) {
      _versionTapCount = 0;
      _firstVersionTapTime = null;

      // Navigate to dev ASR screen.
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => const DevAsrScreen()),
      );
    }
  }

  Future<void> _exportData() async {
    setState(() => _isExporting = true);
    try {
      final jsonString = await exportReviewData(
        weakItemRepo: ref.read(weakItemRepoProvider),
        planRepo: ref.read(planRepoProvider),
        historyRepo: ref.read(reviewHistoryRepoProvider),
      );

      // Copy to clipboard for the user to paste anywhere.
      await Clipboard.setData(ClipboardData(text: jsonString));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'تم تصدير البيانات. تم نسخها إلى الحافظة.',
            ),
            backgroundColor: AppTheme.primaryGreen,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في التصدير: $e'),
            backgroundColor: AppTheme.wordError,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _importData() async {
    // Show a dialog to paste JSON data.
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استيراد البيانات'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'الصق بيانات النسخة الاحتياطية هنا:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 8,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '{"version":1,...}',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('استيراد'),
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty) return;

    setState(() => _isImporting = true);
    try {
      final summary = await importReviewData(
        jsonString: result,
        weakItemRepo: ref.read(weakItemRepoProvider),
        planRepo: ref.read(planRepoProvider),
        historyRepo: ref.read(reviewHistoryRepoProvider),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم استيراد البيانات بنجاح.\n$summary'),
            backgroundColor: AppTheme.primaryGreen,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الاستيراد: $e'),
            backgroundColor: AppTheme.wordError,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RecitationModeSection(
                    currentMode: _settings!.defaultMode,
                    onModeChanged: (mode) {
                      ref.read(recitationModeProvider.notifier).state = mode;
                      _saveSettings(_settings!.copyWith(defaultMode: mode));
                    },
                  ),
                  const SizedBox(height: 16),
                  _ReviewSettingsSection(
                    settings: _settings!,
                    onChanged: _saveSettings,
                  ),
                  const SizedBox(height: 16),
                  _DataBackupSection(
                    isExporting: _isExporting,
                    isImporting: _isImporting,
                    onExport: _exportData,
                    onImport: _importData,
                  ),
                  const SizedBox(height: 16),
                  _AboutSection(onVersionTap: _onVersionTap),
                ],
              ),
            ),
    );
  }
}

class _RecitationModeSection extends StatelessWidget {
  final RecitationMode currentMode;
  final ValueChanged<RecitationMode> onModeChanged;

  const _RecitationModeSection({
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'وضع التسميع',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.inkDark,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'تحكم في صرامة مطابقة الكلمات',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            ...RecitationMode.values.map((mode) {
              final label = switch (mode) {
                RecitationMode.easy => 'سهل',
                RecitationMode.normal => 'عادي',
                RecitationMode.strict => 'صارم',
              };
              final description = switch (mode) {
                RecitationMode.easy => 'تسامح أكبر في مطابقة الكلمات',
                RecitationMode.normal => 'توازن بين الدقة والتسامح',
                RecitationMode.strict => 'دقة عالية في المطابقة',
              };
              final config = RecitationConfig.presets[mode]!;

              return RadioListTile<RecitationMode>(
                value: mode,
                groupValue: currentMode,
                onChanged: (v) => onModeChanged(v!),
                title: Text(label),
                subtitle: Text(
                  '$description\n'
                  'حد التشابه: ${(config.levThreshold * 100).round()}% • '
                  'حد الثقة: ${(config.confFloor * 100).round()}%',
                  style: const TextStyle(fontSize: 12),
                ),
                activeColor: AppTheme.primaryGreen,
                contentPadding: EdgeInsets.zero,
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _ReviewSettingsSection extends StatelessWidget {
  final UserSettings settings;
  final ValueChanged<UserSettings> onChanged;

  const _ReviewSettingsSection({
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'إعدادات المراجعة',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.inkDark,
              ),
            ),
            const SizedBox(height: 16),
            // Daily target
            Row(
              children: [
                const Expanded(
                  child: Text('الهدف اليومي للمراجعة'),
                ),
                DropdownButton<int>(
                  value: settings.dailyTarget,
                  items: [3, 5, 10, 15, 20, 25].map((n) {
                    return DropdownMenuItem(
                      value: n,
                      child: Text('$n آية'),
                    );
                  }).toList(),
                  onChanged: (v) => onChanged(settings.copyWith(dailyTarget: v!)),
                ),
              ],
            ),
            const Divider(),
            // Weakness threshold
            Row(
              children: [
                const Expanded(
                  child: Text('حد الضعف'),
                ),
                DropdownButton<double>(
                  value: settings.weaknessThreshold,
                  items: [1.0, 1.5, 2.0, 3.0, 4.0].map((n) {
                    return DropdownMenuItem(
                      value: n,
                      child: Text(n.toStringAsFixed(1)),
                    );
                  }).toList(),
                  onChanged: (v) => onChanged(settings.copyWith(weaknessThreshold: v!)),
                ),
              ],
            ),
            const Divider(),
            // Mastery horizon
            Row(
              children: [
                const Expanded(
                  child: Text('مدة الإتقان (أيام)'),
                ),
                DropdownButton<int>(
                  value: settings.masteryHorizonDays,
                  items: [14, 21, 30, 45, 60].map((n) {
                    return DropdownMenuItem(
                      value: n,
                      child: Text('$n يوم'),
                    );
                  }).toList(),
                  onChanged: (v) => onChanged(settings.copyWith(masteryHorizonDays: v!)),
                ),
              ],
            ),
            const Divider(),
            // Merge contiguous
            SwitchListTile(
              title: const Text('دمج الآيات المتجاورة'),
              subtitle: const Text(
                'دمج الآيات المتجاورة الضعيفة في عنصر مراجعة واحد',
                style: TextStyle(fontSize: 12),
              ),
              value: settings.mergeContiguous,
              onChanged: (v) => onChanged(settings.copyWith(mergeContiguous: v)),
              activeColor: AppTheme.primaryGreen,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

class _DataBackupSection extends StatelessWidget {
  final bool isExporting;
  final bool isImporting;
  final VoidCallback onExport;
  final VoidCallback onImport;

  const _DataBackupSection({
    required this.isExporting,
    required this.isImporting,
    required this.onExport,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.backup, color: AppTheme.primaryGreen, size: 22),
                SizedBox(width: 8),
                Text(
                  'النسخ الاحتياطي للبيانات',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.inkDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'تصدير بيانات المراجعة والخطط إلى الحافظة، '
              'أو استيرادها من نسخة احتياطية سابقة.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isExporting ? null : onExport,
                    icon: isExporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_download),
                    label: const Text('تصدير'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isImporting ? null : onImport,
                    icon: isImporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_upload),
                    label: const Text('استيراد'),
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

class _AboutSection extends StatelessWidget {
  final VoidCallback onVersionTap;

  const _AboutSection({required this.onVersionTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'حول التطبيق',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.inkDark,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'تسميع - تطبيق اختبار حفظ القرآن الكريم',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 8),
            const Text(
              'يستخدم التطبيق تقنية التعرف على الكلام على الجهاز '
              'لمتابعة تلاوتك كلمة بكلمة. يعمل بدون انترنت.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            // Version row — tap 7 times within 3 seconds to open dev ASR screen.
            // Uses plain onTap (not onLongPress) to avoid gesture-arena conflicts.
            GestureDetector(
              onTap: onVersionTap,
              behavior: HitTestBehavior.opaque,
              child: const Row(
                children: [
                  Text(
                    'الإصدار: 1.0.0',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
