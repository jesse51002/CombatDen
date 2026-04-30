import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';

/// Two-tone progress bar: a dim segment showing prior progress, a solid
/// segment showing the gain from this class, and an empty track behind.
class RankProgressBar extends StatelessWidget {
  const RankProgressBar({
    super.key,
    required this.previousFraction,
    required this.currentFraction,
  });

  /// Progress before this class (0..1) — drawn dim.
  final double previousFraction;

  /// Total progress including this class (0..1) — drawn solid up to here.
  final double currentFraction;

  static const double _height = 21;

  @override
  Widget build(BuildContext context) {
    final prev = previousFraction.clamp(0.0, 1.0);
    final curr = currentFraction.clamp(prev, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(_height),
      child: Container(
        height: _height,
        color: DesignConstants.card,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            return Stack(
              children: [
                Container(
                  width: maxWidth * curr,
                  color: DesignConstants.primaryColor,
                ),
                Container(
                  width: maxWidth * prev,
                  color: DesignConstants.darkPrimary,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
