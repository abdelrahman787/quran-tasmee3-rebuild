/// Mushaf screen — browse all 114 surahs, view ayah text, and select a
/// surah to start a recitation session.
///
/// Phase 6: Full Quran Uthmani text is loaded from the JSON asset. Surah
/// cards lazy-load ayah text on expand. Long surahs (e.g. Al-Baqarah with
/// 286 ayahs) use paginated display to avoid rendering all tiles at once.
/// A search bar lets users quickly find any surah by name or number.
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
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final availableSurahs = ref.watch(availableSurahsProvider);

    // Filter surahs based on search query
    final filteredSurahs = _searchQuery.isEmpty
        ? availableSurahs
        : availableSurahs.where((s) {
            final q = _searchQuery.toLowerCase();
            return s.name.contains(_searchQuery) ||
                s.englishName.toLowerCase().contains(q) ||
                s.number.toString() == _searchQuery;
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('المصحف'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfoDialog(context),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'ابحث عن سورة بالاسم أو الرقم...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primaryGreen),
                ),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade800
                    : Colors.grey.shade50,
              ),
            ),
          ),
        ),
      ),
      body: availableSurahs.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : filteredSurahs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text(
                        'لا توجد نتائج',
                        style: TextStyle(
                            fontSize: 16, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredSurahs.length,
                  itemBuilder: (context, index) {
                    final surah = filteredSurahs[index];
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
          'يعمل التطبيق بدون انترنت. يحتوي على نص المصحف كاملاً (114 سورة).',
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

class _SurahCard extends StatefulWidget {
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
  State<_SurahCard> createState() => _SurahCardState();
}

class _SurahCardState extends State<_SurahCard> {
  /// Paginated ayah display: show first 20 ayahs, load more on scroll.
  static const int _pageSize = 20;
  int _visibleCount = _pageSize;
  List<AyahData>? _cachedAyat;

  @override
  void didUpdateWidget(_SurahCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset pagination when surah changes or card collapses
    if (oldWidget.surah.number != widget.surah.number ||
        (oldWidget.isExpanded && !widget.isExpanded)) {
      _visibleCount = _pageSize;
      _cachedAyat = null;
    }
  }

  List<AyahData> _getAyat() {
    if (_cachedAyat == null) {
      _cachedAyat = QuranData.getAyatForSurah(widget.surah.number);
    }
    return _cachedAyat!;
  }

  @override
  Widget build(BuildContext context) {
    final ayat = widget.isExpanded ? _getAyat() : <AyahData>[];
    final visibleAyat = ayat.take(_visibleCount).toList();
    final hasMore = ayat.length > _visibleCount;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          InkWell(
            onTap: widget.onToggle,
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
                        '${widget.surah.number}',
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
                          widget.surah.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.inkDark,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.surah.englishName} • ${widget.surah.ayahCount} آية • ${widget.surah.revelationType == 'Meccan' ? 'مكية' : 'مدنية'}',
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
                    widget.isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AppTheme.primaryGreen,
                  ),
                ],
              ),
            ),
          ),
          if (widget.isExpanded) ...[
            const Divider(height: 1),
            if (ayat.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Ayah list (paginated)
                    for (final ayah in visibleAyat) ...[
                      _AyahTile(
                        ayah: ayah,
                        isExpanded: widget.expandedAyah == ayah.ayah,
                        onTap: () => widget.onAyahTap(ayah.ayah),
                      ),
                      if (ayah != visibleAyat.last) const SizedBox(height: 8),
                    ],
                    // Load more button
                    if (hasMore) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _visibleCount += _pageSize;
                            });
                          },
                          icon: const Icon(Icons.expand_more),
                          label: Text(
                            'عرض المزيد (${ayat.length - _visibleCount} آية متبقية)',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // Start recitation button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: widget.onStartRecitation,
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
