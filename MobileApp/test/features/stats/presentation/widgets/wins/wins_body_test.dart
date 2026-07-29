import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/wins/wins_body.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';

const _stats = MockWinsStats(
  title: 'Today’s wins',
  subtitle: 'The grind never stops',
  heroAsset: 'stat_wins_trophy.png',
  tiles: [
    MockWinTile(iconName: 'award', value: '3', label: 'Classes this week'),
    MockWinTile(iconName: 'gift', value: '+160', label: 'Points'),
    MockWinTile(iconName: 'star', value: '4 weeks', label: 'Streak'),
  ],
);

Widget _host({PostClassController? controller}) => MaterialApp(
      home: Scaffold(
        body: WinsBody(stats: _stats, controller: controller),
      ),
    );

void main() {
  /// Sizes the surface like a phone. The card is laid out for one, and the
  /// default 800×600 test window is shorter than any device this Android/iOS-
  /// only app ships on.
  void phoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  group('the wins card releases the scaffold CTA', () {
    testWidgets('the controller stays animating until the cascade lands',
        (tester) async {
      phoneSurface(tester);
      final controller = PostClassController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(controller: controller));
      // Mid-cascade: the CTA must still be hidden, like every sibling card.
      expect(controller.isAnimating, isTrue);

      await tester.pump(const Duration(seconds: 4));
      // Without this the flow's LAST card would have no CTA at all — the
      // scaffold hides it for as long as the controller says it's animating.
      expect(controller.isAnimating, isFalse);

      await tester.pumpAndSettle();
    });

    testWidgets('a tap-to-skip releases it immediately', (tester) async {
      phoneSurface(tester);
      final controller = PostClassController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(controller: controller));
      controller.requestSkip();

      expect(controller.isAnimating, isFalse);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('renders every live tile value it is handed', (tester) async {
      phoneSurface(tester);
      await tester.pumpWidget(_host());
      await tester.pump(const Duration(seconds: 4));

      expect(find.text('Classes this week'), findsOneWidget);
      expect(find.text('Points'), findsOneWidget);
      expect(find.text('Streak'), findsOneWidget);
      // A non-numeric value renders as static text rather than a count-up.
      expect(find.text('4 weeks'), findsOneWidget);

      await tester.pumpAndSettle();
    });
  });
}
