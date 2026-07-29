import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/stats/data/rewards_card_view.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rewards/reward_featured_caption.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rewards/rewards_carousel.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/animation/staggered_reveal.dart';

/// The card once the giftbox has burst: title block, the photo band, and the
/// featured caption under it.
///
/// It FILLS the body area (`SizedBox.expand` + `Spacer`s) rather than centring
/// a min-height column in it — the same structure `PointsBody` and `RankBody`
/// use, and the reason the 3:2 band no longer floats as a small island. The
/// 3:4 split biases the photo slightly above true centre (the standard
/// optical-centre correction) and leaves the caption room without pushing it
/// into the CTA.
class RewardsCardLayout extends StatelessWidget {
  const RewardsCardLayout({
    super.key,
    required this.view,
    required this.controller,
    required this.featuredIndex,
    required this.onPageChanged,
    required this.slideDuration,
  });

  final RewardsCardView view;
  final PageController controller;
  final int featuredIndex;
  final ValueChanged<int> onPageChanged;
  final Duration slideDuration;

  @override
  Widget build(BuildContext context) {
    final carouselDelay =
        CelebrationTimings.revealStagger + CelebrationTimings.revealDuration;
    return SizedBox.expand(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TitleBlock(title: view.title, subtitle: view.subtitle),
          const Spacer(flex: 3),
          // A `Spacer` can't share the outer `Column`'s `spacing:` without
          // gapping around itself, so the band→caption gap lives here.
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingBig,
            children: [
              StaggeredReveal(
                delay: carouselDelay,
                offset: 0,
                child: RewardsCarousel(
                  items: view.slides,
                  controller: controller,
                  onPageChanged: onPageChanged,
                  physics: view.slides.length <= 1
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                ),
              ),
              AnimatedSwitcher(
                duration: slideDuration,
                child: RewardFeaturedCaption(
                  key: ValueKey(featuredIndex),
                  slide: view.slides[featuredIndex],
                  featuredIndex: featuredIndex,
                ),
              ),
            ],
          ),
          const Spacer(flex: 4),
        ],
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        StaggeredReveal(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: DesignConstants.big2,
          ),
        ),
        StaggeredReveal(
          delay: CelebrationTimings.revealStagger,
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DesignConstants.pBig.copyWith(
              color: DesignConstants.text3rd,
            ),
          ),
        ),
      ],
    );
  }
}
