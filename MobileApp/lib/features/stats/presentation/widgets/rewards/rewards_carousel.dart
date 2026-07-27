import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rewards/reward_slide.dart';

/// Swipeable cover-flow reward carousel: the active page is full size and
/// face-on, adjacent pages shrink and tilt away in 3D for depth.
class RewardsCarousel extends StatelessWidget {
  const RewardsCarousel({
    super.key,
    required this.items,
    required this.controller,
    required this.onPageChanged,
  });

  final List<RewardSlide> items;
  final PageController controller;
  final ValueChanged<int> onPageChanged;

  static const double _featuredSize = 208;
  // Reward photos are framed 3:2 — the ratio the store's `RewardImageHero`
  // already uses — so a gym's uploaded artwork is cropped the same way on the
  // store card and on this card. The featured WIDTH is unchanged; the height
  // follows from the ratio, which is what the carousel now reserves.
  static const double _featuredAspect = 1.5;
  static const double _featuredHeight = _featuredSize / _featuredAspect;
  static const double _minScale = 0.56;
  // Maximum y-axis tilt (radians) applied to a page that is one slot away
  // from the active page.
  static const double _maxTilt = 0.6;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _featuredHeight,
      child: PageView.builder(
        controller: controller,
        onPageChanged: onPageChanged,
        physics: const BouncingScrollPhysics(),
        clipBehavior: Clip.none,
        itemBuilder: (context, page) {
          final index = page % items.length;
          return AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              double offset = 0;
              if (controller.hasClients &&
                  controller.position.hasContentDimensions) {
                offset = page -
                    (controller.page ?? controller.initialPage.toDouble());
              } else {
                offset = (page - controller.initialPage).toDouble();
              }
              final clamped = offset.clamp(-1.0, 1.0);
              final t = clamped.abs();
              final scale = 1 - (1 - _minScale) * t;
              final tiltY = -clamped * _maxTilt;
              final transform = Matrix4.identity()
                ..setEntry(3, 2, 0.0015)
                ..rotateY(tiltY)
                ..scaleByDouble(scale, scale, scale, 1);
              return Center(
                child: Transform(
                  alignment: Alignment.center,
                  transform: transform,
                  child: child,
                ),
              );
            },
            child: _RewardSlideImage(
              image: items[index].image,
              width: _featuredSize,
              height: _featuredHeight,
            ),
          );
        },
      ),
    );
  }
}

/// One reward's photo, framed as a rounded rectangle on the card family's
/// [DesignConstants.radiusBig] — the same corner `RewardCard` gives a reward in
/// the store. The box is 3:2 for the same reason: gyms upload rectangular
/// photos, and a square or circular frame crops the sides off every one of
/// them.
class _RewardSlideImage extends StatelessWidget {
  const _RewardSlideImage({
    required this.image,
    required this.width,
    required this.height,
  });

  final ImageProvider image;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: Border.all(
          color: DesignConstants.text,
          width: DesignConstants.buttonBorderSize,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image(
        image: image,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => ColoredBox(color: DesignConstants.card),
      ),
    );
  }
}
