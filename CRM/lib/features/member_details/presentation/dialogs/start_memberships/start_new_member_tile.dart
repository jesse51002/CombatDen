import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// "New member" adder tile for the members step — sits above the link-first
/// tile. A dashed accent border on an accent-soft fill reads as an "add new"
/// affordance. Tapping opens the in-run new-member dialog.
class StartNewMemberTile extends StatelessWidget {
  /// Payer's first name, woven into the subtitle so staff see who the new
  /// member will be authorized under.
  final String payerFirstName;
  final VoidCallback onTap;

  const StartNewMemberTile({
    super.key,
    required this.payerFirstName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusSmall,
      ),
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: DesignConstants.primaryColor,
          radius: DesignConstants.radiusSmall,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: DesignConstants.accentSoft,
            borderRadius: BorderRadius.circular(
              DesignConstants.radiusSmall,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(
              DesignConstants.paddingSmall,
            ),
            child: Row(
              spacing: DesignConstants.spacingMedium,
              children: [
                Icon(
                  Symbols.add_sharp,
                  weight: DesignConstants.iconWeight,
                  size: DesignConstants.iconSizeMedium,
                  color: DesignConstants.primaryColor,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    spacing: DesignConstants.spacingTiny,
                    children: [
                      Text(
                        'New member',
                        style: DesignConstants.pSemibold
                            .copyWith(
                          color: DesignConstants.primaryColor,
                        ),
                      ),
                      Text(
                        'Create someone new, authorize '
                        '$payerFirstName as payer, add them to '
                        'this run.',
                        style: DesignConstants.pSmall.copyWith(
                          color: DesignConstants.text2nd,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Strokes a dashed rounded-rect border (Flutter has no built-in dashed
/// border). Walks the RRect path with `PathMetrics`, painting dash-length
/// segments separated by gaps.
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  static const double _dash = 6;
  static const double _gap = 4;

  _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = DesignConstants.buttonBorder
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + _dash),
          paint,
        );
        distance += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
