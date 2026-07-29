import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/animation/count_up_text.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('a delayed count-up leaves NO timer pending after dispose',
      (tester) async {
    // The reel used to start off a bare `Future.delayed`, which outlives the
    // widget: the callback's `mounted` check kept it harmless, but the timer
    // itself stayed pending. That hangs `pumpAndSettle` and — the assertion
    // here — trips the test binding's "a Timer is still pending even after the
    // widget tree was disposed" check when the test ends without draining it.
    await tester.pumpWidget(
      _host(
        CountUpText(
          target: 42,
          style: DesignConstants.h1,
          delay: const Duration(seconds: 5),
        ),
      ),
    );
    expect(find.byType(CountUpText), findsOneWidget);

    await tester.pumpWidget(_host(const SizedBox.shrink()));
    expect(find.byType(CountUpText), findsNothing);
    // Deliberately no `pump(5s)` here: the point is that nothing is left to
    // drain. If the timer survives disposal, this test fails at teardown.
  });

  testWidgets('an undelayed count-up still rolls to its target',
      (tester) async {
    await tester.pumpWidget(
      _host(CountUpText(target: 7, style: DesignConstants.h1)),
    );
    await tester.pumpAndSettle();

    expect(find.text('7'), findsWidgets);
  });

  testWidgets('a delayed count-up still rolls once its delay elapses',
      (tester) async {
    await tester.pumpWidget(
      _host(
        CountUpText(
          target: 9,
          style: DesignConstants.h1,
          delay: const Duration(milliseconds: 300),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('9'), findsWidgets);
  });
}
