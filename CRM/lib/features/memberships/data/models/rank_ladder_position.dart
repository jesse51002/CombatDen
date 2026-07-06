import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';

/// A resolved leaf on a gym's ladder — a [rank] plus its [subIndex]
/// (`null` when the rank has no effective sub-positions, i.e. the main
/// rank is itself the leaf).
class RankLeaf {
  final MainRank rank;
  final int? subIndex;

  const RankLeaf(this.rank, this.subIndex);
}

/// A member's position on a gym's ladder, and the promotion targets
/// derived from it. The single source of truth for "where are they, and
/// where do they go next" — the [PromotionDialog] (next-sub / next-major
/// menu) and the shared `PromotableMemberRow` (its current → next label)
/// both construct one of these rather than each re-deriving the ladder
/// walk. Mirrors `RanksRepository.applyPromotion`'s own resolution so the
/// UI matches what the backend will actually do.
///
/// Plain Dart, no JSON — this never crosses the wire (like
/// [PromotionChoice]); it is view logic over the loaded ladder.
class RankLadderPosition {
  /// The gym's main ranks, in ladder order (lowest first).
  final List<MainRank> ladder;

  /// The gym's sub-rank type; `none` means no sub-positions gym-wide.
  final RankSubType subRankType;

  /// The member's current MAIN rank id, or `null` when unranked.
  final String? currentMainRankId;

  /// The member's current leaf within that rank, or `null` when the
  /// rank has no sub-ranks (or when unranked).
  final int? currentSubIndex;

  const RankLadderPosition({
    required this.ladder,
    required this.subRankType,
    required this.currentMainRankId,
    required this.currentSubIndex,
  });

  /// True when the member sits on no rank yet.
  bool get isUnranked => currentMainRankId == null;

  /// Whether [rank] carries EFFECTIVE sub-positions — its stored count
  /// is positive AND the gym isn't `none` (which turns sub-ranks off
  /// gym-wide). All leaf/label math keys off this, never the raw count.
  bool _hasSubs(MainRank rank) =>
      subRankType != RankSubType.none && rank.subRankCount > 0;

  /// The member's current main rank row, or `null` when unranked / not
  /// found in the ladder.
  MainRank? get currentMain {
    for (final rank in ladder) {
      if (rank.rankId == currentMainRankId) return rank;
    }
    return null;
  }

  /// The next belt above the current one, or `null` at the top. An
  /// unranked member's "next major" is the lowest belt.
  MainRank? get nextMajor {
    if (ladder.isEmpty) return null;
    if (currentMainRankId == null) return ladder.first;
    final index =
        ladder.indexWhere((r) => r.rankId == currentMainRankId);
    if (index < 0) return ladder.first;
    if (index >= ladder.length - 1) return null;
    return ladder[index + 1];
  }

  /// True when the current belt has a higher sub-position still to earn
  /// (so "next sub-rank" is a real move).
  bool get nextSubEnabled {
    final main = currentMain;
    final sub = currentSubIndex;
    return main != null &&
        _hasSubs(main) &&
        sub != null &&
        sub < main.subRankCount - 1;
  }

  /// The leaf the member currently sits on, or `null` when unranked.
  RankLeaf? get currentLeaf {
    final main = currentMain;
    if (main == null) return null;
    return RankLeaf(main, _hasSubs(main) ? currentSubIndex : null);
  }

  /// The single leaf a one-step Promote lands on: the next sub-position
  /// within the current belt when one remains, else the base leaf of the
  /// next belt. `null` at the very top of the ladder (no further step).
  RankLeaf? get nextLeaf {
    if (nextSubEnabled) {
      return RankLeaf(currentMain!, currentSubIndex! + 1);
    }
    final next = nextMajor;
    if (next == null) return null;
    return RankLeaf(next, _hasSubs(next) ? 0 : null);
  }

  /// The display label for [leaf]: `"Blue Belt"` on a subless leaf,
  /// `"Blue Belt · 2 Stripes"` on a labelled sub-position, and — when
  /// [showBase] is set — `"Blue Belt · Base"` on the bare base leaf of a
  /// sub-using belt (the stripes base renders an empty sub-label, which
  /// the row substitutes with "Base" so a promotion target always shows
  /// its position; the dialog leaves [showBase] off, so its menu keeps
  /// the plain belt name there).
  String leafLabel(RankLeaf leaf, {bool showBase = false}) {
    if (leaf.subIndex == null || !_hasSubs(leaf.rank)) {
      return leaf.rank.name;
    }
    final sub = subRankType.subLabel(leaf.subIndex!);
    if (sub.isEmpty) {
      return showBase ? '${leaf.rank.name} · Base' : leaf.rank.name;
    }
    return '${leaf.rank.name} · $sub';
  }
}
