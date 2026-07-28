import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_badge.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_progress.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_progress_label.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_title.dart';

/// Badge sizes. 100pt is the shipped one; the rest are the same art at
/// the prominence its arrangement gives it.
const double _kBadgeShipped = 100;
const double _kBadgeArc = 120;
const double _kBadgeStacked = 72;
const double _kBadgeTile = 64;

/// How the four next-rank elements — badge, title, progress, label —
/// are grouped. Every value renders all four; only where they sit
/// changes. (`beltHero` is the one arrangement that does not use this:
/// it splits the four across two regions of the screen.)
enum NextRankLayout {
  /// Title and label left, ring-wrapped badge trailing. Ships today.
  badgeTrailing,

  /// A large arc with the belt inside it, text centred beneath.
  arc,

  /// Badge over title, bar and label beneath, left aligned.
  stacked,

  /// Stacked small enough for a board tile.
  tile,
}

/// "Next Rank" — the belt the member is working toward, and how close
/// they are to it.
class NextRankSection extends StatelessWidget {
  const NextRankSection({
    super.key,
    required this.title,
    required this.progressLabel,
    required this.progress,
    required this.badgeAsset,
    this.layout = NextRankLayout.badgeTrailing,
  });

  final String title;
  final String progressLabel;
  final double progress;
  final String badgeAsset;
  final NextRankLayout layout;

  @override
  Widget build(BuildContext context) {
    return switch (layout) {
      NextRankLayout.badgeTrailing => _badgeTrailing(),
      NextRankLayout.arc => _arc(),
      NextRankLayout.stacked => _stacked(),
      NextRankLayout.tile => _tile(),
    };
  }

  Widget _ringBadge(double size) => NextRankProgress(
    progress: progress,
    child: NextRankBadge(badgeAsset: badgeAsset, size: size),
  );

  /// Title over label — the pair travels together in three of the four
  /// arrangements, only its alignment and scale change.
  Widget _words({
    TextAlign align = TextAlign.start,
    bool compact = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align == TextAlign.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        NextRankTitle(title: title, align: align, compact: compact),
        NextRankProgressLabel(
          label: progressLabel,
          align: align,
          compact: compact,
        ),
      ],
    );
  }

  Widget _badgeTrailing() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: DesignConstants.paddingBig),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingMedium,
        children: [
          Expanded(child: _words()),
          _ringBadge(_kBadgeShipped),
        ],
      ),
    );
  }

  Widget _arc() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        NextRankProgress(
          progress: progress,
          layout: NextRankProgressLayout.arc,
          child: NextRankBadge(badgeAsset: badgeAsset, size: _kBadgeArc),
        ),
        _words(align: TextAlign.center),
      ],
    );
  }

  Widget _stacked() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingLarge,
          children: [
            NextRankBadge(badgeAsset: badgeAsset, size: _kBadgeStacked),
            Expanded(child: NextRankTitle(title: title)),
          ],
        ),
        NextRankProgress(
          progress: progress,
          layout: NextRankProgressLayout.bar,
        ),
        NextRankProgressLabel(label: progressLabel),
      ],
    );
  }

  Widget _tile() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        _ringBadge(_kBadgeTile),
        _words(align: TextAlign.center, compact: true),
      ],
    );
  }
}
