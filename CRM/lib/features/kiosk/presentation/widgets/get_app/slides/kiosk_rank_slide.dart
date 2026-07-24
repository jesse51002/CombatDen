import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_showcase_slide.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/slides/kiosk_rank_progress.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/shared/widgets/rank_belt_image.dart';

/// How far a resting rung fades back behind the featured one. Only the ART
/// is dimmed — a rung's NAME is words, so it holds the kiosk's AA colour
/// floor ([DesignConstants.text2nd]) at full opacity instead.
const double _kRestingBeltOpacity = 0.45;

/// One rung of the ladder the "Track rank" slide draws.
///
/// A view model, not a fetched row — [kioskRankSteps] maps the gym's real
/// ladder onto it. An EMPTY ladder is the signal a gym does not run ranks (or
/// the fetch failed), and the slide is then omitted entirely — see
/// `kioskShowcaseSlides`.
class KioskRankStep {
  final String name;
  final String? imageUrl;

  /// The gym's real `classes_to_next_major` for this rung — how many classes
  /// it takes to leave it. Read only for the featured rung, as the progress
  /// bar's denominator, so the requirement on screen is the gym's own.
  final int classesToNext;

  const KioskRankStep({
    required this.name,
    this.imageUrl,
    this.classesToNext = 0,
  });
}

/// Map the gym's ordered main-rank ladder (as the ranks domain returns it) to
/// the slide's rungs. Sub-ranks are deliberately not drawn: the ladder is the
/// gym's MAIN progression.
///
/// It takes no member. This slide is an advertisement, not a readout — see
/// [KioskRankSlide] for why that is deliberate.
List<KioskRankStep> kioskRankSteps(List<MainRank> ladder) => [
      for (final rank in ladder)
        KioskRankStep(
          name: rank.name,
          imageUrl: rank.imageUrl,
          classesToNext: rank.classesToNextMajor,
        ),
    ];

/// Which rung of a [rungCount]-long ladder the slide features.
///
/// Always a MIDDLE one, and deliberately the LOWER middle: for any ladder of
/// two or more rungs that leaves at least one rung ABOVE the featured one, so
/// the progress bar always has a real next belt to name.
int kioskFeaturedRungIndex(int rungCount) => (rungCount - 1) ~/ 2;

/// Slide 4 — "Track rank": the gym's belt ladder with one MIDDLE rung drawn
/// large and un-dimmed over a partly-filled progress bar.
///
/// **Conditional.** It renders only for a gym that really runs ranks — the
/// cubit reads the gym's rank-enabled flag AND its ladder at kiosk entry, and
/// either coming up short omits the slide (and its dot), so a no-ranks gym
/// never sees belts.
///
/// **The featured rung and the progress numbers are ILLUSTRATIVE ON PURPOSE.
/// Do not wire them back to the member.** An earlier pass did read the
/// checked-in member's real rank and their real attendance progress; it was
/// removed deliberately (founder ruling). Kiosk users skew NEW, so real data
/// pinned the highlight to the FIRST rung with an empty bar — the least
/// compelling thing the feature can look like. This panel is a pitch for the
/// app, not a status readout, so it features a middle rung and a satisfying
/// partial bar in every state, and it needs no member data at all: it renders
/// identically whether the modal was opened from the glance or the idle home.
///
/// It is the deliberate EXCEPTION on this showcase, not the pattern — the
/// "Earn rewards" slide draws the gym's REAL cached catalogue and "Book
/// classes" the REAL occurrences the flow loaded. Here the belt names, the
/// belt art and the per-rank thresholds are the gym's own; which rung is
/// featured, and how full the bar is, are not.
///
/// The one hard guard that survives: **nothing on this slide may claim the
/// featured rung or the progress belongs to the person standing there.** A
/// white belt told "you're purple" stops trusting the number instead of
/// wanting it, and that costs the pitch more than the highlight wins — which
/// is why the old "You're here" tag is gone and the copy stays
/// feature-describing.
class KioskRankSlide extends StatelessWidget {
  final List<KioskRankStep> ladder;

  const KioskRankSlide({super.key, required this.ladder});

  @override
  Widget build(BuildContext context) {
    // `kioskShowcaseSlides` never builds this slide for an empty ladder; the
    // guard is here so the widget is safe to hand any list.
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

/// One rung's art over its name. The featured rung is the only one drawn at
/// full size, full opacity and full ink — that contrast IS the emphasis, so
/// no tag is needed (and none may claim the rung).
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
              : DesignConstants.kioskTag.copyWith(
                  fontWeight: FontWeight.w600,
                  color: DesignConstants.text2nd,
                ),
        ),
      ],
    );
  }
}
