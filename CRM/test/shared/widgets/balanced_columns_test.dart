import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/shared/widgets/balanced_columns.dart';

void main() {
  testWidgets('balances columns, stretches fillers, skips '
      'zero-height children', (tester) async {
    const k = [
      Key('l0'), Key('l1'), Key('r0'), Key('r1'), Key('r2'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 432, // colW = (432 - 32) / 2 = 200
            child: BalancedColumns(
              left: const [
                SizedBox(key: Key('l0'), height: 100),
                SizedBox(key: Key('l1'), height: 50),
              ],
              right: const [
                SizedBox(key: Key('r0'), height: 300),
                SizedBox.shrink(key: Key('r1')),
                SizedBox(key: Key('r2'), height: 80),
              ],
              fillerIndexLeft: 1,
              fillerIndexRight: 0,
              columnSpacing: 32,
              rowSpacing: 32,
            ),
          ),
        ),
      ),
    );
    // rightH = 300 + 32 + 80 = 412 (zero child: no gap).
    // leftH = 100 + 32 + 50 = 182 → filler l1 grows to
    // 50 + (412 - 182) = 280.
    expect(tester.getSize(find.byKey(k[1])).height, 280);
    expect(tester.getSize(find.byKey(k[1])).width, 200);
    // Whole widget: 432 x 412.
    final grid = find.byType(BalancedColumns);
    expect(tester.getSize(grid), const Size(432, 412));
    // Positions: l1 at y = 100 + 32; r2 pinned at bottom
    // (y = 300 + 32), right column at x = 232.
    expect(tester.getTopLeft(find.byKey(k[1])).dy, 132);
    expect(tester.getTopLeft(find.byKey(k[4])).dy, 332);
    expect(tester.getTopLeft(find.byKey(k[2])).dx, 232);
    // Columns end flush: 132 + 280 == 332 + 80 == 412.
    expect(tester.getBottomLeft(find.byKey(k[1])).dy, 412);
    expect(tester.getBottomLeft(find.byKey(k[4])).dy, 412);
  });

  testWidgets('no deficit when equal; empty column safe',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 432,
            child: BalancedColumns(
              left: const [
                SizedBox(key: Key('only'), height: 90),
              ],
              right: const [],
              fillerIndexLeft: 0,
              fillerIndexRight: 0,
              columnSpacing: 32,
              rowSpacing: 32,
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(BalancedColumns)),
      const Size(432, 90),
    );
    expect(
      tester.getSize(find.byKey(const Key('only'))).height,
      90,
    );
  });
}
