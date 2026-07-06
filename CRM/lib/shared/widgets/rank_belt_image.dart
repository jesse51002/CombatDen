import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The one renderer for a rank's belt art — reused by the ladder card,
/// the sub-rank strip, the rank-detail hero, the ready-to-promote board,
/// and the member-detail rank section, so a belt reads identically
/// everywhere.
///
/// Belt colour was removed from the model: a belt is an IMAGE now
/// ([imageUrl], a themed belt/crest PNG the backend generates). This
/// widget renders that image on a rounded tile and degrades gracefully
/// when it is missing — a gym mid-migration with no art yet still shows
/// an intentional, neutral belt glyph rather than a broken box or a bare
/// gap. There is deliberately **no** colour swatch fallback.
///
/// The tile is a square of [size] with a hairline border. Loading and
/// error both resolve to the same calm neutral placeholder so the layout
/// never jumps between states.
class RankBeltImage extends StatelessWidget {
  /// The belt art URL (already leaf-resolved by the caller — a per-sub
  /// override or the main rank's image). Null / empty renders the
  /// placeholder.
  final String? imageUrl;

  /// The tile's edge length (square). Defaults to a medium belt.
  final double size;

  /// Corner radius. Defaults to [DesignConstants.radiusSmall]; the large
  /// hero tiles pass [DesignConstants.radiusBig] / [radiusCard].
  final double radius;

  const RankBeltImage({
    super.key,
    required this.imageUrl,
    this.size = 64,
    this.radius = DesignConstants.radiusSmall,
  });

  bool get _hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: DesignConstants.backgroundAlt,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: DesignConstants.line),
      ),
      child: _hasImage
          ? Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _Placeholder(size: size),
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : _Placeholder(size: size),
            )
          : _Placeholder(size: size),
    );
  }
}

/// The neutral belt glyph shown while loading, on error, or when a rank
/// has no art. Deliberately quiet — a rank should look configured even
/// before its themed image lands.
class _Placeholder extends StatelessWidget {
  final double size;

  const _Placeholder({required this.size});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Symbols.workspace_premium_sharp,
        size: size * 0.48,
        color: DesignConstants.text3rd,
        weight: DesignConstants.iconWeight,
      ),
    );
  }
}
