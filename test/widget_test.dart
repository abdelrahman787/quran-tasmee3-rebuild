import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tasmee3_trainer/main.dart';
import 'package:tasmee3_trainer/models/quran_data.dart';

void main() {
  testWidgets('App renders home screen with bottom navigation', (WidgetTester tester) async {
    // Phase 6: QuranData must be loaded before the app can render surahs.
    await QuranData.load();

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
