import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_view_all_action.dart';

/// How a section's title is drawn.
enum VideoSectionHeaderStyle {
  /// Title left, action trailing. Shipped.
  plain,

  /// Title then a hairline rule running to the edge — the section reads
  /// as a band divider rather than a heading.
  divider,

  /// The header rides on an opaque band, so it can sit over artwork.
  overlay,
}

/// A tag section's title, with the "view all" action when the section
/// carries it inline.
class VideoSectionHeader extends StatelessWidget {
  const VideoSectionHeader({
    super.key,
    required this.title,
    this.onViewAllTap,
    this.showViewAll = true,
    this.style = VideoSectionHeaderStyle.plain,
  });

  final String title;
  final VoidCallback? onViewAllTap;

  /// False when the layout places the action elsewhere (a row beneath
  /// the cards, a tile in the grid). The action itself never
  /// disappears — it moves.
  final bool showViewAll;

  final VideoSectionHeaderStyle style;

  @override
  Widget build(BuildContext context) {
    final row = style == VideoSectionHeaderStyle.divider
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: DesignConstants.spacingMedium,
            children: [
              Text(title, style: DesignConstants.h2),
              Expanded(
                child: Container(
                  height: DesignConstants.dividerThickness,
                  color: DesignConstants.divider,
                ),
              ),
              if (showViewAll) VideoViewAllAction(onTap: onViewAllTap),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: Text(title, style: DesignConstants.h2)),
              if (showViewAll) VideoViewAllAction(onTap: onViewAllTap),
            ],
          );

    if (style != VideoSectionHeaderStyle.overlay) return row;
    return ColoredBox(
      color: DesignConstants.popup,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        child: row,
      ),
    );
  }
}
