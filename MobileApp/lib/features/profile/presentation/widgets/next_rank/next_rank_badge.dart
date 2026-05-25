import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:mobile_app/customization/widgets/branded_image.dart';

const double _kBadgeSize = 100;
const double _kImageInset = 22;

/// Circular belt icon with an orange progress arc tracking how close the
/// member is to the next rank.
class NextRankBadge extends StatelessWidget {
  const NextRankBadge({
    super.key,
    required this.badgeAsset,
    required this.progress,
  });

  final String badgeAsset;
  final double progress;

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
              child: BrandedImage(
                slot: CombatDenSlots.nextRankBeltImage,
                fallback: ApiImage.rankAsset(badgeAsset),
                fit: BoxFit.contain,
              ),
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
