/// Home screen with bottom navigation bar.
///
/// Four tabs:
/// 1. Mushaf — browse and select surahs to recite
/// 2. Recite — live recitation session with word-by-word reveal
/// 3. Review — SM-2 spaced repetition review plan
/// 4. Settings — app settings and preferences
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mushaf/mushaf_screen.dart';
import '../recitation/recitation_screen.dart';
import '../review/review_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  final _screens = const [
    MushafScreen(),
    RecitationScreen(),
    ReviewScreen(),
    SettingsScreen(),
  ];

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
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book),
            label: 'المصحف',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.mic),
            label: 'تسميع',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.school),
            label: 'مراجعة',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'إعدادات',
          ),
        ],
      ),
    );
  }
}
