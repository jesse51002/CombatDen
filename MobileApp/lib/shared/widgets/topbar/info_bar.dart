import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:theme_flutter/theme/theme_image.dart';

// The belt art's dimensions (per-asset layout, not a design token).
const double _kBeltWidth = 39;
const double _kBeltHeight = 24;

// The info bar's cell grid is always FOUR columns wide, whatever the tile
// count — the same rule the bottom nav uses.
const int _kInfoBarColumns = 4;

class InfoBar extends StatelessWidget {
  const InfoBar({
    super.key,
    required this.rankBadgeAsset,
    required this.streakDays,
    required this.pointsLabel,
    this.rankImageUrl,
    this.showRank = true,
    this.pointsSpendable = true,
    this.onQrTap,
  });

  final String rankBadgeAsset;

  /// The member's OWN rank art (`rank.image_url` on the profile, already
  /// resolved server-side with the sub-rank override over the main rank's
  /// image). Preferred over the themed slot when present; null on a screen
  /// with no profile, a gym with ranks off, or a rank carrying no image.
  final String? rankImageUrl;

  final int streakDays;
  final String pointsLabel;

  /// Whether the gym runs a rank ladder. False COLLAPSES the belt tile
  /// entirely — a gym with ranks off has no belt to show, and a fallback belt
  /// on every screen would advertise a ladder that doesn't exist. (This is
  /// distinct from the belt's load fallback, which never collapses; see
  /// [_Belt].)
  final bool showRank;

  /// Whether the gym has rewards to spend points on. False makes the points
  /// tile a plain READ-OUT: the number still reflects real attendance, but it
  /// stops being a doorway into an empty store. Same idiom as [onQrTap]'s null
  /// handler — a non-interactive tile is already the info bar's norm.
  final bool pointsSpendable;

  /// Optional tap handler for the QR-code tile. When null the tile is a
  /// static icon (its behavior on every topbar that doesn't opt in).
  final VoidCallback? onQrTap;

  @override
  Widget build(BuildContext context) {
    final points = _IconValueItem(
      slot: CombatDenSlots.singlePoint,
      asset: 'single_point.png',
      value: pointsLabel,
      assetWidth: 22,
      assetHeight: 22,
    );
    final tiles = <Widget>[
      if (showRank)
        _TapTarget(
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.profile),
          child: _RankItem(asset: rankBadgeAsset, imageUrl: rankImageUrl),
        ),
      _TapTarget(
        onTap: () => Navigator.of(context).pushNamed(AppRoutes.profile),
        child: _IconValueItem(
          slot: CombatDenSlots.streakIcon,
          asset: 'streak_icon.png',
          value: '$streakDays',
          assetWidth: 22,
          assetHeight: 30,
        ),
      ),
      if (pointsSpendable)
        _TapTarget(
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.pointsStore),
          child: points,
        )
      else
        points,
      _QrCodeItem(onTap: onQrTap),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // A tile is ALWAYS a quarter of the bar, and the row is centred — the
        // same rule as the bottom nav. At four tiles this is pixel-identical
        // to an `Expanded` split; at three it leaves a symmetric gutter rather
        // than stretching three tiles across the screen.
        final cellWidth = constraints.maxWidth / _kInfoBarColumns;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final tile in tiles) SizedBox(width: cellWidth, child: tile),
          ],
        );
      },
    );
  }
}

class _TapTarget extends StatelessWidget {
  const _TapTarget({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: child,
    );
  }
}

class _RankItem extends StatelessWidget {
  const _RankItem({required this.asset, this.imageUrl});

  final String asset;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Center(child: _Belt(asset: asset, imageUrl: imageUrl)),
    );
  }
}

/// The belt art: the member's own rank [imageUrl] via
/// [CachedNetworkImageProvider], falling back to the themed slot (bundled
/// [asset] under it) when absent or on a load error — the same idiom
/// `RankHeader._Belt` and `NextRankBadge._Belt` use on the profile.
///
/// At a RANK-ENABLED gym the belt is permanent topbar chrome, so missing or
/// failed ARTWORK degrades to the themed belt instead of collapsing (unlike
/// the creator avatar / gym logo tile, where an absent image is simply
/// omitted) — an empty gap in the info bar would read as broken. That rule is
/// about artwork only: when the gym runs no rank ladder at all the whole tile
/// is gone before this widget is ever built (see `InfoBar.showRank`).
class _Belt extends StatelessWidget {
  const _Belt({required this.asset, this.imageUrl});

  final String asset;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) return _ThemedBelt(asset: asset);
    return Image(
      image: CachedNetworkImageProvider(url),
      width: _kBeltWidth,
      height: _kBeltHeight,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => _ThemedBelt(asset: asset),
    );
  }
}

class _ThemedBelt extends StatelessWidget {
  const _ThemedBelt({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: ThemeImage.image(
        CombatDenSlots.rankBelt,
        fallback: ApiImage.rankAsset(asset),
      ),
      width: _kBeltWidth,
      height: _kBeltHeight,
      fit: BoxFit.contain,
    );
  }
}

class _IconValueItem extends StatelessWidget {
  const _IconValueItem({
    required this.slot,
    required this.asset,
    required this.value,
    required this.assetWidth,
    required this.assetHeight,
  });

  final String slot;
  final String asset;
  final String value;
  final double assetWidth;
  final double assetHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingSmall,
        children: [
          Text(value, style: DesignConstants.p),
          Image(
            image: ThemeImage.image(slot, fallback: ApiImage.asset(asset)),
            width: assetWidth,
            height: assetHeight,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }
}

class _QrCodeItem extends StatelessWidget {
  const _QrCodeItem({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final icon = SizedBox(
      height: 30,
      child: Center(
        child: Image(
          image: ThemeImage.image(
            CombatDenSlots.iconQrcode,
            fallback: ApiImage.asset('icon_qrcode.png'),
          ),
          height: 30,
          fit: BoxFit.contain,
        ),
      ),
    );
    // Null handler → the exact prior behavior: a plain, non-interactive icon.
    if (onTap == null) return icon;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: icon,
    );
  }
}
