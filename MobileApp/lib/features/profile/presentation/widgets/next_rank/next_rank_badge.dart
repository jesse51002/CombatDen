import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:theme_flutter/theme/theme_image.dart';

const double _kBadgeSize = 100;

/// The image sits this fraction of the box in from every edge, so the
/// belt keeps its inset from the progress stroke at any size. At the
/// shipped 100pt badge this is the 22pt inset the screen has today.
const double _kInsetRatio = 0.22;

/// The belt art for the NEXT rank, in a square box.
///
/// The badge is only the belt. Whatever tracks progress AROUND it —
/// the shipped ring, a large arc, a bar — is [NextRankProgress], so a
/// layout can pair the same badge with any of those treatments without
/// the badge knowing which one it got.
class NextRankBadge extends StatelessWidget {
  const NextRankBadge({
    super.key,
    required this.badgeAsset,
    this.size = _kBadgeSize,
  });

  final String badgeAsset;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Padding(
        padding: EdgeInsets.all(size * _kInsetRatio),
        child: Center(
          child: Image(
            image: ThemeImage.image(
              CombatDenSlots.nextRankBeltImage,
              fallback: ApiImage.rankAsset(badgeAsset),
            ),
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
