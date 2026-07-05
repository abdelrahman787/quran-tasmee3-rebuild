/// Home screen with bottom navigation bar.
///
/// Four tabs:
/// 1. Mushaf — browse and select surahs to recite
/// 2. Recite — live recitation session with word-by-word reveal
/// 3. Review — SM-2 spaced repetition review plan
/// 4. Settings — app settings and preferences
///
/// Hidden dev screen: long-press the Settings tab icon 5 times within
/// 3 seconds to access the ASR dev testing screen (Gate 1/2).
/// This is a dev-only feature and is not shown to end users.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mushaf/mushaf_screen.dart';
import '../recitation/recitation_screen.dart';
import '../review/review_screen.dart';
import '../settings/settings_screen.dart';

// Conditional import: real dev screen on mobile (dart:io), stub on web.
// Both files export DevAsrScreen with the same API.
import '../dev_asr/dev_asr_screen_stub.dart'
    if (dart.library.io) '../dev_asr/dev_asr_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  // Hidden dev screen access: track long-press count on Settings tab
  int _settingsLongPressCount = 0;
  DateTime? _firstLongPressTime;

  final _screens = const [
    MushafScreen(),
    RecitationScreen(),
    ReviewScreen(),
    SettingsScreen(),
  ];

  void _onSettingsLongPress() {
    final now = DateTime.now();

    // Reset count if more than 3 seconds since first press
    if (_firstLongPressTime != null &&
        now.difference(_firstLongPressTime!).inSeconds > 3) {
      _settingsLongPressCount = 0;
    }

    if (_settingsLongPressCount == 0) {
      _firstLongPressTime = now;
    }

    _settingsLongPressCount++;

    if (_settingsLongPressCount >= 5) {
      _settingsLongPressCount = 0;
      _firstLongPressTime = null;

      // Navigate to dev ASR screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const DevAsrScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.menu_book),
            label: 'المصحف',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.mic),
            label: 'تسميع',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.school),
            label: 'مراجعة',
          ),
          BottomNavigationBarItem(
            icon: GestureDetector(
              onLongPress: _onSettingsLongPress,
              child: const Icon(Icons.settings),
            ),
            label: 'إعدادات',
          ),
        ],
      ),
    );
  }
}
