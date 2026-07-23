import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_showcase_slide.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/shared/widgets/rank_belt_image.dart';

/// One rung of the ladder the "Track rank" slide draws.
///
/// A view model, not a fetched row — [kioskRankSteps] maps the gym's real
/// ladder onto it. An EMPTY ladder is the signal a gym does not run ranks (or
/// the fetch failed), and the slide is then omitted entirely — see
/// `kioskShowcaseSlides`.
class KioskRankStep {
  final String name;
  final String? imageUrl;

  /// The member's current rank — drawn larger, tagged, and un-dimmed.
  final bool isCurrent;

  const KioskRankStep({
    required this.name,
    this.imageUrl,
    this.isCurrent = false,
  });
}

/// Map the gym's ordered main-rank ladder (as the ranks domain returns it) to
/// the slide's rungs, tagging [currentRankId] as "You're here".
///
/// A null [currentRankId] — the modal opened from the idle home, where no
/// member is known, or a member with no rank assigned — simply leaves every
/// rung untagged: the ladder still markets the belt journey, and no rung is
/// guessed. Sub-ranks are deliberately not drawn: the ladder is the gym's
/// MAIN progression, which is what the mockup's belt strip shows.
List<KioskRankStep> kioskRankSteps(
  List<MainRank> ladder, {
  String? currentRankId,
}) =>
    [
      for (final rank in ladder)
        KioskRankStep(
          name: rank.name,
          imageUrl: rank.imageUrl,
          isCurrent: currentRankId != null && rank.rankId == currentRankId,
        ),
    ];

/// Slide 4 — "Track rank": the gym's belt ladder with the member's current
/// rung called out (mockup `.belt-strip`).
///
/// **Conditional.** It renders only for a gym that really runs ranks — the
/// cubit reads the gym's rank-enabled flag AND its ladder at kiosk entry, and
/// either coming up short omits the slide (and its dot), so a no-ranks gym
/// never sees belts.
///
/// The mockup's progress bar ("14 / 25 classes to Purple") is deliberately NOT
/// drawn: the kiosk holds no promotion-progress data, and a bar filled with an
/// invented fraction is exactly the fabricated member data this screen must
/// not show. Add it when real progress is available.
class KioskRankSlide extends StatelessWidget {
  final List<KioskRankStep> ladder;

  const KioskRankSlide({super.key, required this.ladder});

  @override
  Widget build(BuildContext context) {
    return KioskSlideBody(
      content: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [for (final step in ladder) _Belt(step: step)],
        ),
      ),
      caption: 'Track your journey to the next belt.',
    );
  }
}

class _Belt extends StatelessWidget {
  final KioskRankStep step;

  const _Belt({required this.step});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        if (step.isCurrent) const _HerePill(),
        Opacity(
          opacity: step.isCurrent ? 1 : 0.45,
          child: RankBeltImage(
            imageUrl: step.imageUrl,
            size: step.isCurrent
                ? DesignConstants.rankBeltMedium
                : DesignConstants.rankBeltXSmall,
          ),
        ),
        Text(
          step.name,
          style: DesignConstants.pSmallSemibold.copyWith(
            color: step.isCurrent
                ? DesignConstants.primaryColor
                : DesignConstants.text3rd,
          ),
        ),
      ],
    );
  }
}

class _HerePill extends StatelessWidget {
  const _HerePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingTiny,
      ),
      decoration: ShapeDecoration(
        color: DesignConstants.primaryColor,
        shape: const StadiumBorder(),
      ),
      child: Text(
        'You\'re here',
        style: DesignConstants.pSmallBold.copyWith(
          color: DesignConstants.onAccent,
        ),
      ),
    );
  }
}
