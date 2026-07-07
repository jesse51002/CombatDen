import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/models/rank_ladder_position.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';

/// Covers the shared current → next-leaf resolution + label formatting
/// that both the promotable member row and the promotion dialog rely on.
void main() {
  MainRank rank(String id, int order, {int subs = 0}) => MainRank(
        rankId: id,
        gymId: 'gym',
        mainRankNumOrder: order,
        name: switch (order) {
          0 => 'White Belt',
          1 => 'Blue Belt',
          _ => 'Purple Belt',
        },
        classesToNextMajor: 40,
        subRankCount: subs,
        createdAt: DateTime(2026),
      );

  RankLadderPosition pos({
    required List<MainRank> ladder,
    required RankSubType type,
    required String? mainId,
    required int? sub,
  }) =>
      RankLadderPosition(
        ladder: ladder,
        subRankType: type,
        currentMainRankId: mainId,
        currentSubIndex: sub,
      );

  group('stripes gym (base always shown as "Base")', () {
    final ladder = [rank('w', 0, subs: 5), rank('b', 1, subs: 5)];

    test('base leaf → next stripe within the same belt', () {
      final p = pos(
          ladder: ladder, type: RankSubType.stripes, mainId: 'w', sub: 0);
      expect(p.leafLabel(p.currentLeaf!, showBase: true), 'White Belt · Base');
      expect(p.leafLabel(p.nextLeaf!, showBase: true), 'White Belt · 1 Stripe');
    });

    test('mid stripe → next stripe', () {
      final p = pos(
          ladder: ladder, type: RankSubType.stripes, mainId: 'w', sub: 2);
      expect(
          p.leafLabel(p.currentLeaf!, showBase: true), 'White Belt · 2 Stripes');
      expect(
          p.leafLabel(p.nextLeaf!, showBase: true), 'White Belt · 3 Stripes');
    });

    test('top stripe of a belt → base of the next belt', () {
      final p = pos(
          ladder: ladder, type: RankSubType.stripes, mainId: 'w', sub: 4);
      expect(
          p.leafLabel(p.currentLeaf!, showBase: true), 'White Belt · 4 Stripes');
      expect(p.leafLabel(p.nextLeaf!, showBase: true), 'Blue Belt · Base');
    });

    test('top of ladder → no next leaf', () {
      final p = pos(
          ladder: ladder, type: RankSubType.stripes, mainId: 'b', sub: 4);
      expect(p.nextLeaf, isNull);
    });
  });

  test('div gym labels 1-indexed divisions', () {
    final ladder = [rank('w', 0, subs: 3)];
    final p =
        pos(ladder: ladder, type: RankSubType.div, mainId: 'w', sub: 0);
    expect(p.leafLabel(p.currentLeaf!, showBase: true), 'White Belt · Div 1');
    expect(p.leafLabel(p.nextLeaf!, showBase: true), 'White Belt · Div 2');
  });

  test('none gym is main-to-main, no sub part', () {
    final ladder = [rank('w', 0, subs: 5), rank('b', 1, subs: 5)];
    final p =
        pos(ladder: ladder, type: RankSubType.none, mainId: 'w', sub: null);
    expect(p.currentLeaf!.subIndex, isNull);
    expect(p.leafLabel(p.currentLeaf!, showBase: true), 'White Belt');
    expect(p.leafLabel(p.nextLeaf!, showBase: true), 'Blue Belt');
  });

  test('dialog omits the base label (showBase: false)', () {
    final ladder = [rank('w', 0, subs: 5)];
    final p = pos(
        ladder: ladder, type: RankSubType.stripes, mainId: 'w', sub: 0);
    // The dialog's menu keeps the plain belt name on a base leaf.
    expect(p.leafLabel(p.currentLeaf!), 'White Belt');
    expect(p.leafLabel(p.currentLeaf!, showBase: true), 'White Belt · Base');
  });
}
