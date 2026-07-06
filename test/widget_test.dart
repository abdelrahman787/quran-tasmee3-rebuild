import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tasmee3_trainer/main.dart';
import 'package:tasmee3_trainer/models/quran_data.dart';

void main() {
  testWidgets('App renders home screen with bottom navigation', (WidgetTester tester) async {
    // Seed a tiny fake dataset instead of loading the 1.4 MB JSON asset.
    // The widget test only verifies that the bottom-nav labels render —
    // it does not exercise surah text, so a single fake ayah is enough.
    QuranData.seedForTesting({
      '1:1': const AyahData(
        surah: 1,
        ayah: 1,
        uthmaniText: 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
        page: 1,
      ),
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: Tasmee3App(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify bottom navigation items exist
    expect(find.text('المصحف'), findsWidgets);
    expect(find.text('تسميع'), findsWidgets);
    expect(find.text('مراجعة'), findsWidgets);
    expect(find.text('إعدادات'), findsWidgets);
  });
}
