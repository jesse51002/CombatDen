import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_showcase_slide.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/slides/kiosk_rank_progress.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/shared/widgets/rank_belt_image.dart';

/// How far a resting rung's ART fades behind the featured one. Only the art —
/// a rung's NAME is words, so it holds the kiosk's AA colour floor
/// ([DesignConstants.text2nd]) at full opacity.
const double _kRestingBeltOpacity = 0.45;

/// One rung of the ladder the "Track rank" slide draws — a view model mapped
/// from the gym's real ladder by [kioskRankSteps], not a fetched row.
class KioskRankStep {
  final String name;
  final String? imageUrl;

  /// The gym's real `classes_to_next_major` for this rung. Read only for the
  /// featured rung, as the progress bar's denominator.
  final int classesToNext;

  const KioskRankStep({
    required this.name,
    this.imageUrl,
    this.classesToNext = 0,
  });
}

/// Map the gym's ordered main-rank ladder to the slide's rungs. Sub-ranks are
/// deliberately not drawn (the ladder is the gym's MAIN progression), and it
/// takes no member, by design — see [KioskRankSlide].
List<KioskRankStep> kioskRankSteps(List<MainRank> ladder) => [
      for (final rank in ladder)
        KioskRankStep(
          name: rank.name,
          imageUrl: rank.imageUrl,
          classesToNext: rank.classesToNextMajor,
        ),
    ];

/// Which rung of a [rungCount]-long ladder the slide features: always a MIDDLE
/// one, and deliberately the LOWER middle, so any ladder of two or more rungs
/// leaves a real next belt above it for the progress bar to name.
int kioskFeaturedRungIndex(int rungCount) => (rungCount - 1) ~/ 2;

/// Slide 4 — "Track rank": the gym's belt ladder with one MIDDLE rung drawn
/// large and un-dimmed over a partly-filled progress bar. It renders only for
/// a gym that really runs ranks (rank-enabled flag AND a ladder).
///
/// **The featured rung and the progress numbers are ILLUSTRATIVE ON PURPOSE —
/// do not wire them to the member** (founder ruling). Kiosk users skew NEW, so
/// real member data pins the highlight to the FIRST rung with an empty bar,
/// the least compelling the feature can look; this is a pitch for the app, not
/// a status readout, and it needs no member data at all. Belt names, art and
/// per-rank thresholds are still the gym's own — the deliberate exception on
/// this showcase (see `kioskShowcaseSlides`), not the pattern.
///
/// The hard guard: nothing here may claim the featured rung or the progress
/// belongs to the person standing there. A white belt told "you're purple"
/// stops trusting the number instead of wanting it.
class KioskRankSlide extends StatelessWidget {
  final List<KioskRankStep> ladder;

  const KioskRankSlide({super.key, required this.ladder});

  @override
  Widget build(BuildContext context) {
    // Safety only: `kioskShowcaseSlides` skips this for an empty ladder.
    if (ladder.isEmpty) return const SizedBox.shrink();
    final featured = kioskFeaturedRungIndex(ladder.length);
    final next = featured + 1 < ladder.length ? ladder[featured + 1] : null;
    return KioskSlideBody(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingMedium,
              children: [
                for (var i = 0; i < ladder.length; i++)
                  _Belt(step: ladder[i], featured: i == featured),
              ],
            ),
          ),
          KioskRankProgress(
            target: ladder[featured].classesToNext,
            nextRankName: next?.name,
          ),
        ],
      ),
      caption: 'Every class you take counts toward the next belt.',
    );
  }
}

/// One rung's art over its name. The featured rung is the only one at full
/// size, opacity and ink — that contrast IS the emphasis, so no tag is needed
/// (and none may claim the rung).
class _Belt extends StatelessWidget {
  final KioskRankStep step;
  final bool featured;

  const _Belt({required this.step, required this.featured});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Opacity(
          opacity: featured ? 1 : _kRestingBeltOpacity,
          child: RankBeltImage(
            imageUrl: step.imageUrl,
            size: featured
                ? DesignConstants.rankBeltLarge
                : DesignConstants.rankBeltXSmall,
          ),
        ),
        Text(
          step.name,
          style: featured
              ? DesignConstants.kioskLabel.copyWith(
                  fontWeight: FontWeight.w700,
                )
              : DesignConstants.tag.copyWith(
                  fontWeight: FontWeight.w600,
                  color: DesignConstants.text2nd,
                ),
        ),
      ],
    );
  }
}
