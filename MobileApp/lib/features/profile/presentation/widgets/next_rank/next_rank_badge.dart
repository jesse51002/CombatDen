import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:theme_flutter/theme/theme_image.dart';

const double _kBadgeSize = 100;
const double _kImageInset = 22;

/// Circular belt icon with an orange progress arc tracking how close the
/// member is to the next rank.
///
/// The belt is the gym's REAL next-rank art ([imageUrl], disk-cached) when the
/// payload carries one; the themed slot (and, under it, the bundled
/// [badgeAsset]) is the fallback for the top of the ladder, a rank with no
/// image, or a load error.
class NextRankBadge extends StatelessWidget {
  const NextRankBadge({
    super.key,
    required this.badgeAsset,
    required this.progress,
    this.imageUrl,
  });

  final String badgeAsset;
  final double progress;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kBadgeSize,
      height: _kBadgeSize,
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(_kImageInset),
            child: Center(
              child: _Belt(imageUrl: imageUrl, badgeAsset: badgeAsset),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _ProgressArcPainter(
                progress: progress,
                color: DesignConstants.text,
                strokeWidth: DesignConstants.buttonBorderSize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The next-rank belt art: the payload's `next_rank_image_url` via
/// [CachedNetworkImageProvider], falling back to the themed slot (bundled
/// asset under it) when absent or on a load error — the same ladder the shared
/// `RankBeltImage` runs for the member's CURRENT belt, but on the different
/// `nextRankBeltImage` slot. Behaviourally identical; folding it onto the
/// shared widget (via its `slot` parameter) is a separate change.
class _Belt extends StatelessWidget {
  const _Belt({required this.imageUrl, required this.badgeAsset});

  final String? imageUrl;
  final String badgeAsset;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) return _ThemedBelt(badgeAsset: badgeAsset);
    return Image(
      image: CachedNetworkImageProvider(url),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => _ThemedBelt(badgeAsset: badgeAsset),
    );
  }
}

class _ThemedBelt extends StatelessWidget {
  const _ThemedBelt({required this.badgeAsset});

  final String badgeAsset;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: ThemeImage.image(
        CombatDenSlots.nextRankBeltImage,
        fallback: ApiImage.rankAsset(badgeAsset),
      ),
      fit: BoxFit.contain,
    );
  }
}

class _ProgressArcPainter extends CustomPainter {
  _ProgressArcPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final rect = Offset.zero & size;
    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      -1.5708, // -pi/2, top
      progress * 6.2832, // 2*pi
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressArcPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
