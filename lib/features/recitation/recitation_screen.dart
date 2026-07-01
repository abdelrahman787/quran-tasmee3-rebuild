/// Recitation screen — the core feature.
///
/// Displays the selected surah's words with live coloring:
///  - Gray: not yet revealed (not recited)
///  - Dark: correctly recited (revealed)
///  - Red: confirmed error (substitution)
///  - Orange: soft error (attempt 2)
///  - Green outline: current cursor position
///
/// Buttons:
///  - Start/Pause/Resume session
///  - Reveal Next Word (manual forget)
///  - Reveal Full Ayah (manual forget)
///  - End Session → Report
///
/// The screen wires the [RecitationController] from the core package
/// to the UI via [SessionStore] (Riverpod state notifier).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quran_tasmee3_core/recitation/recitation_controller.dart';
import 'package:quran_tasmee3_core/recitation/session_report.dart';

import '../../app/app_theme.dart';
import '../../app/providers.dart';
import '../../models/quran_data.dart';
import '../../services/fake_asr_service.dart';
import '../../services/session_store.dart';
import '../report/report_screen.dart';

class RecitationScreen extends ConsumerStatefulWidget {
  const RecitationScreen({super.key});

  @override
  ConsumerState<RecitationScreen> createState() => _RecitationScreenState();
}

class _RecitationScreenState extends ConsumerState<RecitationScreen> {
  bool _sessionActive = false;

  @override
  Widget build(BuildContext context) {
    final surahNum = ref.watch(selectedSurahProvider);
    final surah = QuranData.getSurah(surahNum);
    final sessionState = ref.watch(sessionStoreProvider);
    final scope = ref.watch(recitationScopeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(surah != null ? 'تسميع ${surah.name}' : 'تسميع'),
        actions: [
          if (_sessionActive)
            IconButton(
              icon: const Icon(Icons.stop_circle),
              onPressed: () => _endSession(),
              tooltip: 'إنهاء الجلسة',
            ),
        ],
      ),
      body: scope.isEmpty
          ? _buildEmptyState()
          : _buildRecitationBody(context, surah, scope, sessionState),
      floatingActionButton: _sessionActive
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _startSession(scope),
              icon: const Icon(Icons.mic),
              label: const Text('بدء التسميع'),
              backgroundColor: AppTheme.primaryGreen,
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.menu_book,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'اختر سورة من المصحف',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'انتقل إلى تبويب المصحف لاختيار السورة',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecitationBody(
    BuildContext context,
    SurahMeta? surah,
    List scope,
    SessionState sessionState,
  ) {
    return Column(
      children: [
        // Status bar
        _buildStatusBar(sessionState, scope.length),
        // Ayah text display
        Expanded(
          child: Container(
            color: AppTheme.parchment,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildAyahText(scope, sessionState),
            ),
          ),
        ),
        // Control buttons
        if (_sessionActive) _buildControls(sessionState),
      ],
    );
  }

  Widget _buildStatusBar(SessionState state, int totalWords) {
    final statusText = switch (state.status) {
      RecitationStatus.idle => 'جاهز',
      RecitationStatus.listening => 'يستمع...',
      RecitationStatus.matching => 'يطابق...',
      RecitationStatus.revealing => 'يكشف الكلمات',
      RecitationStatus.error => 'خطأ',
      RecitationStatus.completed => 'اكتمل',
      RecitationStatus.paused => 'متوقف مؤقتاً',
    };

    final statusColor = switch (state.status) {
      RecitationStatus.listening => AppTheme.primaryGreen,
      RecitationStatus.matching => AppTheme.goldAccent,
      RecitationStatus.revealing => AppTheme.primaryGreen,
      RecitationStatus.error => AppTheme.wordError,
      RecitationStatus.completed => AppTheme.primaryGreen,
      RecitationStatus.paused => Colors.grey,
      RecitationStatus.idle => Colors.grey,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white,
      child: Row(
        children: [
          // Status indicator
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
          const Spacer(),
          // Progress
          if (state.revealedIndices.isNotEmpty)
            Text(
              '${state.revealedIndices.length}/$totalWords',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          // Silence indicator
          if (state.silenceIndicatorVisible) ...[
            const SizedBox(width: 12),
            const Icon(
              Icons.timer,
              color: AppTheme.goldAccent,
              size: 20,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAyahText(List scope, SessionState state) {
    // Group words by ayah
    final ayahGroups = <MapEntry<String, List<int>>>[];
    final ayahMap = <String, List<int>>{};

    for (var i = 0; i < scope.length; i++) {
      final word = scope[i] as dynamic;
      final key = '${word.surah}:${word.ayah}';
      ayahMap.putIfAbsent(key, () => []).add(i);
    }
    ayahGroups.addAll(ayahMap.entries);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: ayahGroups.map((entry) {
          final parts = entry.key.split(':');
          final surahNum = int.parse(parts[0]);
          final ayahNum = int.parse(parts[1]);
          final surah = QuranData.getSurah(surahNum);

          return Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Ayah header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.goldAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${surah?.name ?? ''} • آية $ayahNum',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.primaryGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Words
                Wrap(
                  spacing: 4,
                  runSpacing: 8,
                  alignment: WrapAlignment.start,
                  children: entry.value.map((i) {
                    final word = scope[i] as dynamic;
                    final isRevealed = state.revealedIndices.contains(i);
                    final isCursor = state.cursor == i && state.isActive;
                    final isError = state.lastError != null &&
                        state.lastError!.wordId == word.wordId;

                    return _WordPill(
                      text: word.display.isNotEmpty ? word.display : word.norm,
                      isRevealed: isRevealed,
                      isCursor: isCursor,
                      isError: isError &&
                          state.lastError!.severity != ErrorSeverity.transient,
                      isSoftError: isError &&
                          state.lastError!.severity == ErrorSeverity.soft,
                      isPronunciation: isError &&
                          state.lastError!.severity == ErrorSeverity.flag,
                    );
                  }).toList(),
                ),
                // Ayah end marker
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'ۖ $ayahNum',
                    style: const TextStyle(
                      fontSize: 18,
                      color: AppTheme.goldAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildControls(SessionState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -2),
            blurRadius: 8,
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Pause/Resume
            if (state.isListening || state.isPaused)
              _ControlButton(
                icon: state.isPaused ? Icons.play_arrow : Icons.pause,
                label: state.isPaused ? 'استئناف' : 'إيقاف',
                color: AppTheme.primaryGreen,
                onTap: () {
                  if (state.isPaused) {
                    ref.read(sessionStoreProvider.notifier).resume();
                  } else {
                    ref.read(sessionStoreProvider.notifier).pause();
                  }
                },
              ),
            // Reveal next word
            if (state.isActive)
              _ControlButton(
                icon: Icons.lightbulb_outline,
                label: 'كشف كلمة',
                color: AppTheme.goldAccent,
                onTap: () => ref.read(sessionStoreProvider.notifier).revealNextWord(),
              ),
            // Reveal full ayah
            if (state.isActive)
              _ControlButton(
                icon: Icons.visibility,
                label: 'كشف الآية',
                color: AppTheme.goldAccent,
                onTap: () => ref.read(sessionStoreProvider.notifier).revealFullAyah(),
              ),
            // End session
            if (state.isActive || state.isPaused)
              _ControlButton(
                icon: Icons.check_circle,
                label: 'إنهاء',
                color: AppTheme.wordError,
                onTap: _endSession,
              ),
          ],
        ),
      ),
    );
  }

  void _startSession(List scope) {
    final config = ref.read(recitationConfigProvider);
    final asrService = ref.read(asrServiceProvider);
    final logger = ref.read(sessionLoggerProvider);
    final clock = ref.read(clockProvider);

    // Set scope on the fake ASR
    if (asrService is FakeAsrServiceImpl) {
      asrService.setScope(scope.cast());
    }

    ref.read(sessionStoreProvider.notifier).startSession(
      scope: scope.cast(),
      mode: config,
      clock: clock,
      asrService: asrService,
      logger: logger,
    );

    setState(() => _sessionActive = true);
  }

  void _endSession() {
    final report = ref.read(sessionStoreProvider.notifier).stopAndReport();
    setState(() => _sessionActive = false);

    if (report != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReportScreen(report: report),
        ),
      );
    }
  }
}

class _WordPill extends StatelessWidget {
  final String text;
  final bool isRevealed;
  final bool isCursor;
  final bool isError;
  final bool isSoftError;
  final bool isPronunciation;

  const _WordPill({
    required this.text,
    required this.isRevealed,
    required this.isCursor,
    required this.isError,
    required this.isSoftError,
    required this.isPronunciation,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    Color? borderColor;
    double borderWidth = 0;
    FontWeight fontWeight = FontWeight.normal;

    if (isError) {
      color = AppTheme.wordError;
      fontWeight = FontWeight.bold;
    } else if (isSoftError) {
      color = AppTheme.wordSoftError;
      fontWeight = FontWeight.w600;
    } else if (isPronunciation) {
      color = AppTheme.wordPronunciation;
    } else if (isRevealed) {
      color = AppTheme.wordRevealed;
      fontWeight = FontWeight.w500;
    } else {
      color = AppTheme.wordUnrevealed;
    }

    if (isCursor) {
      borderColor = AppTheme.wordCurrent;
      borderWidth = 2;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        border: borderColor != null
            ? Border.all(color: borderColor, width: borderWidth)
            : null,
        borderRadius: BorderRadius.circular(6),
        color: isCursor
            ? AppTheme.wordCurrent.withValues(alpha: 0.08)
            : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 24,
          height: 1.8,
          fontFamily: 'Amiri',
          color: color,
          fontWeight: fontWeight,
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
