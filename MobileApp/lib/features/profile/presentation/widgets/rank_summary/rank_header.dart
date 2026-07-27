import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';

// The member's belt art dimensions (per-asset layout, not a design token).
const double _kBeltWidth = 77;
const double _kBeltHeight = 50;

// Bundled fallback belt, shown when the rank has no image_url (or it fails).
const String _kFallbackBeltAsset = 'profile_rank_belt_gold.png';

/// Belt image + main rank name, with the sub-rank label below. The belt is the
/// member's own rank art ([imageUrl], disk-cached) with a bundled fallback.
class RankHeader extends StatelessWidget {
  const RankHeader({
    super.key,
    required this.imageUrl,
    required this.rankTitle,
    this.rankSubtitle,
  });

  final String? imageUrl;
  final String rankTitle;
  final String? rankSubtitle;

  @override
  Widget build(BuildContext context) {
    final sub = rankSubtitle;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        _Belt(imageUrl: imageUrl),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(rankTitle, style: DesignConstants.h1),
            if (sub != null && sub.isNotEmpty)
              Text(
                sub,
                style: DesignConstants.h2.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The belt art: the member's `image_url` via [CachedNetworkImageProvider],
/// falling back to a bundled belt when absent or on a load error.
class _Belt extends StatelessWidget {
  const _Belt({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) return const _FallbackBelt();
    return Image(
      image: CachedNetworkImageProvider(url),
      width: _kBeltWidth,
      height: _kBeltHeight,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const _FallbackBelt(),
    );
  }
}

class _FallbackBelt extends StatelessWidget {
  const _FallbackBelt();

  @override
  Widget build(BuildContext context) {
    return Image(
      image: ApiImage.rankAsset(_kFallbackBeltAsset),
      width: _kBeltWidth,
      height: _kBeltHeight,
      fit: BoxFit.contain,
    );
  }
}
