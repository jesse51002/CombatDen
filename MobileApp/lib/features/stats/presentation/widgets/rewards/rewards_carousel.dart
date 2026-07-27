import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_ready_tag.dart';
import 'package:mobile_app/features/stats/data/rewards_card_view.dart';

/// Swipeable cover-flow reward carousel: the active page is full size and
/// face-on, adjacent pages shrink and tilt away in 3D for depth.
///
/// Each slide's frame is its affordability meter (see [_RewardRingPainter]),
/// and a redeemable slide additionally carries a [RewardReadyTag]. Both ride
/// the 3D transform, so a neighbour reads as a coloured chip — which is the
/// "which of these can I actually get" glance the card exists for.
class RewardsCarousel extends StatelessWidget {
  const RewardsCarousel({
    super.key,
    required this.items,
    required this.controller,
    required this.onPageChanged,
    this.physics = const BouncingScrollPhysics(),
  });

  final List<RewardsCardSlide> items;
  final PageController controller;
  final ValueChanged<int> onPageChanged;

  /// `NeverScrollableScrollPhysics` on a one-item catalog: there is nowhere
  /// to swipe to, and the infinite `PageView` would happily slide from a photo
  /// to the identical photo.
  final ScrollPhysics physics;

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
        physics: physics,
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
              item: items[index],
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
///
/// The ring and the tags are drawn OUTSIDE the clipped photo, so a failed
/// image still carries its full affordability state.
class _RewardSlideImage extends StatelessWidget {
  const _RewardSlideImage({
    required this.item,
    required this.width,
    required this.height,
  });

  final RewardsCardSlide item;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final locked = item.affordance == RewardAffordance.locked;
    final redeemable = item.affordance == RewardAffordance.redeemable;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        foregroundPainter: _RewardRingPainter(
          progress: locked ? item.progress : 1,
          ringColor:
              redeemable ? DesignConstants.accent : DesignConstants.text,
          trackColor: locked ? DesignConstants.divider : null,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(DesignConstants.radiusBig),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image(
                image: item.slide.image,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    ColoredBox(color: DesignConstants.card),
              ),
            ),
            Positioned(
              top: DesignConstants.spacingMedium,
              left: DesignConstants.spacingMedium,
              right: DesignConstants.spacingMedium,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (redeemable) const RewardReadyTag(),
                  const Spacer(),
                  Flexible(
                    child: RewardPriceTag(label: item.slide.discountLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The frame IS the progress meter: closed when the member can have the
/// reward, partly drawn when they can't.
///
/// Deliberately mirrors `_ProgressArcPainter` in
/// `features/profile/presentation/widgets/next_rank/next_rank_badge.dart` —
/// same `buttonBorderSize` stroke, same top-centre start, same clockwise
/// direction, same [StrokeCap.round]. It is a separate class only because the
/// geometry is an RRect, not a circle.
class _RewardRingPainter extends CustomPainter {
  _RewardRingPainter({
    required this.progress,
    required this.ringColor,
    required this.trackColor,
  });

  /// 0..1. 1.0 closes the ring, which is the redeemable / unknown look.
  final double progress;
  final Color ringColor;

  /// The unfilled remainder's hairline, or null when the ring is closed.
  final Color? trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    // A `Border.all(width: w)` paints inward from the box edge; a stroke of
    // width `w` centred on a rect deflated by `w/2` occupies the identical
    // band, so the closed ring is pixel-identical to the frame that shipped.
    final stroke = DesignConstants.buttonBorderSize;
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(stroke / 2),
      Radius.circular(DesignConstants.radiusBig),
    );
    final path = _ringPath(rrect);

    final track = trackColor;
    if (track != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = DesignConstants.dividerThickness
          ..strokeCap = StrokeCap.round,
      );
    }

    final paint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (progress >= 1) {
      canvas.drawPath(path, paint);
      return;
    }
    if (progress <= 0) return;
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * progress),
      paint,
    );
  }

  /// Built by hand so it STARTS at top-centre and runs clockwise, which makes
  /// `extractPath(0, len * progress)` exactly right with no start offset and
  /// no wraparound branch.
  Path _ringPath(RRect r) {
    final rad = r.tlRadiusX;
    return Path()
      ..moveTo(r.center.dx, r.top)
      ..lineTo(r.right - rad, r.top)
      ..arcToPoint(Offset(r.right, r.top + rad), radius: Radius.circular(rad))
      ..lineTo(r.right, r.bottom - rad)
      ..arcToPoint(Offset(r.right - rad, r.bottom),
          radius: Radius.circular(rad))
      ..lineTo(r.left + rad, r.bottom)
      ..arcToPoint(Offset(r.left, r.bottom - rad),
          radius: Radius.circular(rad))
      ..lineTo(r.left, r.top + rad)
      ..arcToPoint(Offset(r.left + rad, r.top), radius: Radius.circular(rad))
      ..lineTo(r.center.dx, r.top);
  }

  @override
  bool shouldRepaint(covariant _RewardRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.ringColor != ringColor ||
        oldDelegate.trackColor != trackColor;
  }
}
