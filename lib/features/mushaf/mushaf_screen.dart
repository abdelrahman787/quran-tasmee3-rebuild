/// Mushaf screen — browse surahs, view ayah text, and select a surah
/// to start a recitation session.
///
/// In production, this would use QCF V2 per-page fonts with the full
/// Uthmani text. For the web preview, we use system Arabic fonts with
/// embedded text for a subset of surahs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart';
import '../../app/providers.dart';
import '../../models/quran_data.dart';

class MushafScreen extends ConsumerStatefulWidget {
  const MushafScreen({super.key});

  @override
  ConsumerState<MushafScreen> createState() => _MushafScreenState();
}

class _MushafScreenState extends ConsumerState<MushafScreen> {
  int? _selectedSurah;
  int? _expandedAyah;

  @override
  Widget build(BuildContext context) {
    final availableSurahs = ref.watch(availableSurahsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('المصحف'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: availableSurahs.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: availableSurahs.length,
              itemBuilder: (context, index) {
                final surah = availableSurahs[index];
                return _SurahCard(
                  surah: surah,
                  isExpanded: _selectedSurah == surah.number,
                  expandedAyah: _expandedAyah,
                  onToggle: () {
                    setState(() {
                      _selectedSurah = _selectedSurah == surah.number
                          ? null
                          : surah.number;
                      _expandedAyah = null;
                    });
                  },
                  onAyahTap: (ayahNum) {
                    setState(() {
                      _expandedAyah = _expandedAyah == ayahNum
                          ? null
                          : ayahNum;
                    });
                  },
                  onStartRecitation: () => _startRecitation(surah),
                );
              },
            ),
    );
  }

  void _startRecitation(SurahMeta surah) {
    // Set the selected surah in the provider
    ref.read(selectedSurahProvider.notifier).state = surah.number;

    // Show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('بدء تسميع سورة ${surah.name} — انتقل إلى تبويب التسميع'),
        backgroundColor: AppTheme.primaryGreen,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('عن التطبيق'),
        content: const Text(
          'تطبيق تسميع القرآن الكريم\n\n'
          'يستخدم التطبيق تقنية التعرف على الكلام على الجهاز '
          'لمتابعة تلاوتك كلمة بكلمة وتنبيهك للأخطاء.\n\n'
          'يعمل التطبيق بدون انترنت.',
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }
}

class _SurahCard extends StatelessWidget {
  final SurahMeta surah;
  final bool isExpanded;
  final int? expandedAyah;
  final VoidCallback onToggle;
  final ValueChanged<int> onAyahTap;
  final VoidCallback onStartRecitation;

  const _SurahCard({
    required this.surah,
    required this.isExpanded,
    required this.expandedAyah,
    required this.onToggle,
    required this.onAyahTap,
    required this.onStartRecitation,
  });

  @override
  Widget build(BuildContext context) {
    final ayat = QuranData.getAyatForSurah(surah.number);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Surah number badge
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.goldAccent,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${surah.number}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Surah name and info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          surah.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.inkDark,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${surah.englishName} • ${surah.ayahCount} آية • ${surah.revelationType == 'Meccan' ? 'مكية' : 'مدنية'}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Expand icon
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AppTheme.primaryGreen,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            if (ayat.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('لا يوجد نص متاح لهذه السورة في العرض التجريبي'),
              )
            else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Ayah list
                    for (final ayah in ayat) ...[
                      _AyahTile(
                        ayah: ayah,
                        isExpanded: expandedAyah == ayah.ayah,
                        onTap: () => onAyahTap(ayah.ayah),
                      ),
                      if (ayah != ayat.last) const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 16),
                    // Start recitation button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onStartRecitation,
                        icon: const Icon(Icons.mic),
                        label: const Text('بدء التسميع'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _AyahTile extends StatelessWidget {
  final AyahData ayah;
  final bool isExpanded;
  final VoidCallback onTap;

  const _AyahTile({
    required this.ayah,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isExpanded
              ? AppTheme.parchmentDark
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.goldAccent.withValues(alpha: 0.15),
                  ),
                  child: Center(
                    child: Text(
                      '${ayah.ayah}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    ayah.uthmaniText,
                    style: const TextStyle(
                      fontSize: 20,
                      height: 2.0,
                      fontFamily: 'Amiri',
                      color: AppTheme.inkDark,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                ),
              ],
            ),
            if (isExpanded) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 40),
                child: Text(
                  'الكلمات: ${ayah.toExpectedWords().length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
