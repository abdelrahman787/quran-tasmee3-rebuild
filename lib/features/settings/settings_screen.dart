/// Settings screen — user preferences and app configuration.
///
/// Settings:
///  - Recitation mode (easy/normal/strict)
///  - Daily review target
///  - Weakness threshold
///  - Mastery horizon (days)
///  - Merge contiguous ayat toggle
///  - About / version info
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quran_tasmee3_core/recitation/recitation_config.dart';
import 'package:quran_tasmee3_core/review/settings.dart';

import '../../app/app_theme.dart';
import '../../app/providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  UserSettings? _settings;
  bool _isLoading = true;

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
                  _AboutSection(),
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

class _AboutSection extends StatelessWidget {
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
              'تسميع - تطبيق اختبار حفظ القرآن الكين',
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
            const Row(
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
          ],
        ),
      ),
    );
  }
}
