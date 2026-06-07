import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

// Fixed tile width — the MAX width a tile ever takes, so a short last row
// keeps tile size instead of stretching across the pane.
const double _kTileWidth = 280;

/// A reflowing grid of fixed-width video tiles — left-aligned, so a short
/// last row keeps tile width instead of stretching. Takes pre-built tiles so
/// the live feed (API videos) and "Your videos" (mock uploads) share it.
class VideoWrapGrid extends StatelessWidget {
  final List<Widget> tiles;

  const VideoWrapGrid({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = _kTileWidth.clamp(0.0, constraints.maxWidth);
        return Wrap(
          spacing: DesignConstants.spacingLarge,
          runSpacing: DesignConstants.spacingBig,
          children: [
            for (final tile in tiles) SizedBox(width: tileWidth, child: tile),
          ],
        );
      },
    );
  }
}
