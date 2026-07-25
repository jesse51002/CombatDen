import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_home_columns.dart';

/// The home's band structure has a second job beyond co-centring the two
/// bodies: it must not reserve height for a foot no half fills. Both halves
/// are footless on the live home (the app-adoption strip spans the whole
/// screen), so the band AND the spacing above it collapse and hand that height
/// to the flexible middle — while the slot survives for any half that does
/// carry a foot.
void main() {
  const headKey = ValueKey<String>('head');
  const bodyKey = ValueKey<String>('body');
  const footKey = ValueKey<String>('foot');

  const double headHeight = 20;
  const double bodyHeight = 40;
  const double footHeight = 24;

  Future<void> pumpColumns(WidgetTester tester, {Widget? foot}) async {
    await tester.binding.setSurfaceSize(const Size(1180, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: KioskHomeColumns(
              left: KioskHomeHalf(
                head: const SizedBox(key: headKey, height: headHeight),
                body: const SizedBox(key: bodyKey, height: bodyHeight),
                foot: foot,
              ),
              right: const KioskHomeHalf(
                head: SizedBox(height: headHeight),
                body: SizedBox(height: bodyHeight),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the feet band costs NOTHING when neither half fills it',
      (tester) async {
    await pumpColumns(tester);

    expect(tester.takeException(), isNull);

    final columns = tester.getRect(find.byType(KioskHomeColumns));
    final body = tester.getRect(find.byKey(bodyKey));

    // The bodies' band runs to the very bottom of the composition: no empty
    // band under it, and no spacing reserved above one.
    expect(body.bottom, moreOrLessEquals(columns.bottom, epsilon: 0.5));
    expect(
      columns.height,
      moreOrLessEquals(
        headHeight + DesignConstants.spacingBig + bodyHeight,
        epsilon: 0.5,
      ),
    );
  });

  testWidgets('a half that DOES carry a foot still gets its band',
      (tester) async {
    await pumpColumns(
      tester,
      foot: const SizedBox(key: footKey, height: footHeight),
    );

    expect(tester.takeException(), isNull);

    final columns = tester.getRect(find.byType(KioskHomeColumns));
    final body = tester.getRect(find.byKey(bodyKey));
    final foot = tester.getRect(find.byKey(footKey));

    // The band comes back with the column's own spacing above it and closes
    // the composition.
    expect(
      foot.top - body.bottom,
      moreOrLessEquals(DesignConstants.spacingBig, epsilon: 0.5),
    );
    expect(foot.bottom, moreOrLessEquals(columns.bottom, epsilon: 0.5));
    expect(
      columns.height,
      moreOrLessEquals(
        headHeight +
            DesignConstants.spacingBig +
            bodyHeight +
            DesignConstants.spacingBig +
            footHeight,
        epsilon: 0.5,
      ),
    );
  });

  testWidgets('the two bodies stay co-centred either way', (tester) async {
    await pumpColumns(
      tester,
      foot: const SizedBox(key: footKey, height: footHeight),
    );

    // A foot on ONE half never drags its body off the shared centre.
    final left = tester.getRect(find.byKey(bodyKey));
    final right = tester.getRect(
      find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.height == bodyHeight,
        description: 'a body box',
      ).last,
    );

    expect(left.center.dy, moreOrLessEquals(right.center.dy, epsilon: 0.5));
  });
}
