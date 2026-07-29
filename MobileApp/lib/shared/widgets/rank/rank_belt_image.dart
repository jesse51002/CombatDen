import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:theme_flutter/theme/theme_image.dart';

/// **The** belt-art rule, in one widget: the member's OWN rank art
/// ([imageUrl], disk-cached via [CachedNetworkImageProvider]) first, then the
/// themed [slot] (`CombatDenSlots.rankBelt`), then the bundled [asset] under
/// that. The fallback is taken both when the URL is absent and when it fails
/// to load.
///
/// Every belt in the app resolves this way — the topbar's `InfoBar` tile, the
/// profile's `RankHeader`, the post-class rank card and the promotion card's
/// two sides. Don't fork a fifth rule; use this and, if a site needs a
/// different themed slot, pass [slot].
///
/// A blank / whitespace-only URL is ABSENT, not broken (the rule
/// `creatorAvatarProvider` sets), so it falls back silently rather than
/// resolving an empty request.
///
/// It carries no width/height on purpose: the promotion and rank cards size it
/// frame-by-frame as it flies from centre stage into a measured slot, and both
/// branches must hand the animation ONE widget that fills whatever box it is
/// given. A fixed-size site wraps it in its own `SizedBox`.
class RankBeltImage extends StatelessWidget {
  const RankBeltImage({
    super.key,
    required this.imageUrl,
    required this.asset,
    this.slot = CombatDenSlots.rankBelt,
  });

  /// The member's own belt art, already resolved server-side (a per-sub-rank
  /// override over the main rank's image), or a promotion's snapshot URL.
  final String? imageUrl;

  /// The bundled floor under the themed slot, e.g. `stat_rank_belt.png`.
  final String asset;

  /// The themed slot between the two. Defaults to the app's one belt slot.
  final String slot;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim() ?? '';
    if (url.isEmpty) return _ThemedBelt(slot: slot, asset: asset);
    return Image(
      image: CachedNetworkImageProvider(url),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => _ThemedBelt(slot: slot, asset: asset),
    );
  }
}

class _ThemedBelt extends StatelessWidget {
  const _ThemedBelt({required this.slot, required this.asset});

  final String slot;
  final String asset;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: ThemeImage.image(slot, fallback: ApiImage.rankAsset(asset)),
      fit: BoxFit.contain,
    );
  }
}
