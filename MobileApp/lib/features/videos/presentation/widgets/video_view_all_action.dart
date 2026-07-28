import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// How the "view all" affordance is drawn. Presentation only — every
/// style opens the same tag list.
enum VideoViewAllStyle {
  /// Underlined text sitting inline in the section header. Shipped.
  link,

  /// A full-width action row beneath the section's cards.
  row,

  /// A grid cell, so the action reads as the last tile of a mosaic.
  tile,
}

/// The section's "view all" affordance: one action, three treatments.
class VideoViewAllAction extends StatelessWidget {
  const VideoViewAllAction({
    super.key,
    this.onTap,
    this.style = VideoViewAllStyle.link,
  });

  final VoidCallback? onTap;
  final VideoViewAllStyle style;

  static const String _kLabel = 'view all';
  static const double _kTileAspect = 16 / 9;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: switch (style) {
        VideoViewAllStyle.link => const _Label(),
        VideoViewAllStyle.row => _Surface(
          padding: EdgeInsets.symmetric(
            vertical: DesignConstants.paddingSmall,
          ),
          child: const Center(child: _Label()),
        ),
        VideoViewAllStyle.tile => AspectRatio(
          aspectRatio: _kTileAspect,
          child: _Surface(child: const Center(child: _Label())),
        ),
      },
    );
  }
}

class _Label extends StatelessWidget {
  const _Label();

  @override
  Widget build(BuildContext context) {
    return Text(
      VideoViewAllAction._kLabel,
      style: DesignConstants.p.copyWith(
        decoration: TextDecoration.underline,
        decorationColor: DesignConstants.text,
      ),
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: child,
    );
  }
}
