import 'package:flutter/material.dart';
import 'package:crm/showcase/celebrations/showcase_celebration_stats.dart';
import 'package:crm/showcase/showcase_assets.dart';
import 'package:crm/showcase/showcase_tokens.dart';

/// Clone of MobileApp's `RewardsCarousel`: swipeable cover-flow reward
/// carousel — the active page is full size and face-on, adjacent pages shrink
/// and tilt away in 3D for depth.
class RewardsCarousel extends StatelessWidget {
  const RewardsCarousel({
    super.key,
    required this.items,
    required this.controller,
    required this.onPageChanged,
  });

  final List<ShowcaseRewardItem> items;
  final PageController controller;
  final ValueChanged<int> onPageChanged;

  static const double _featuredSize = 208;
  static const double _minScale = 0.56;
  // Maximum y-axis tilt (radians) applied to a page that is one slot away
  // from the active page.
  static const double _maxTilt = 0.6;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _featuredSize,
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
            child: _RewardCircle(
              imageUrl: items[index].imageUrl,
              imageAsset: items[index].imageAsset,
              size: _featuredSize,
            ),
          );
        },
      ),
    );
  }
}

class _RewardCircle extends StatelessWidget {
  const _RewardCircle({
    this.imageUrl,
    required this.imageAsset,
    required this.size,
  });

  final String? imageUrl;
  final String imageAsset;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: ShowcaseTokens.text,
          width: ShowcaseTokens.buttonBorderSize,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image(
        // Injected gym reward photo when present, else the bundled fallback.
        image: ShowcaseAsset.imageOrNetwork(imageUrl, imageAsset),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => ColoredBox(color: ShowcaseTokens.card),
      ),
    );
  }
}
