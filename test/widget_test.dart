// اختبارات أساسية لتطبيق «أخبار المنطقة».
//
// التطبيق نفسه (NewsApp) يعتمد على تهيئة Firebase، لذا لا يمكن تشغيله كما هو
// داخل بيئة الاختبار. نكتفي هنا باختبار المكوّنات والدوال المستقلة عن Firebase.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:news_app/main.dart';

void main() {
  group('timeAgo', () {
    test('يعيد «الآن» عندما يكون التاريخ فارغاً', () {
      expect(timeAgo(null), 'الآن');
    });

    test('يعيد «الآن» لفارق أقل من دقيقة', () {
      final now = DateTime.now().subtract(const Duration(seconds: 20));
      expect(timeAgo(now), 'الآن');
    });

    test('يعيد الدقائق لفارق أقل من ساعة', () {
      final t = DateTime.now().subtract(const Duration(minutes: 5));
      expect(timeAgo(t), 'قبل 5 دقيقة');
    });

    test('يعيد الساعات لفارق أقل من يوم', () {
      final t = DateTime.now().subtract(const Duration(hours: 3));
      expect(timeAgo(t), 'قبل 3 ساعة');
    });

    test('يعيد «أمس» لفارق يوم واحد', () {
      final t = DateTime.now().subtract(const Duration(days: 1, hours: 1));
      expect(timeAgo(t), 'أمس');
    });

    test('يعيد الأيام لفارق أقل من شهر', () {
      final t = DateTime.now().subtract(const Duration(days: 10));
      expect(timeAgo(t), 'قبل 10 يوم');
    });
  });

  group('Post.fromDoc', () {
    // نموذج بسيط لمحاكاة مستند Firestore دون الحاجة إلى الحزمة.
    test('يملأ القيم الافتراضية عند غياب الحقول', () {
      // نتحقق فقط من الدوال المستقلة؛ التحقق الكامل من Post يحتاج إلى
      // DocumentSnapshot حقيقي، وهو غير متاح هنا.
    }, skip: 'يتطلب DocumentSnapshot من cloud_firestore');
  });

  testWidgets('AppLogo يُرسم بالحجم المطلوب', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: AppLogo(size: 64)),
        ),
      ),
    );

    expect(find.byType(AppLogo), findsOneWidget);
    expect(find.byIcon(Icons.campaign_rounded), findsOneWidget);

    final sizedContainer = tester.widget<Container>(
      find.descendant(
        of: find.byType(AppLogo),
        matching: find.byType(Container),
      ),
    );
    expect(sizedContainer.constraints?.maxWidth, 64);
  });
}
