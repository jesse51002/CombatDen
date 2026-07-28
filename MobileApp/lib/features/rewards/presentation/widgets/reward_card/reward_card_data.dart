import 'package:flutter/foundation.dart';

/// How a reward card is arranged.
///
/// PRESENTATION ONLY. Every value renders the identical element set from
/// the identical [RewardCardData]: the image, one price tag, the title,
/// the points cost, and exactly ONE redeem action that belongs to the
/// card. A value may move those and change their prominence. It may not
/// drop one, add one, or hand one to somebody else — including the
/// screen layout that placed the card.
enum RewardCardLayout {
  /// Image on top, title / cost / action stacked beneath. Ships today.
  imageTop,

  /// Full-width row: square thumb leading, action trailing.
  thumbLeft,

  /// Tall single-focus poster; the image takes the height it is given.
  poster,

  /// Dense square tile for a multi-column band.
  tile,

  /// Full-bleed promoted card; text and action ride the image.
  hero,
}

/// Everything a reward card renders. Identical for every
/// [RewardCardLayout] — a layout rearranges this payload, it never
/// reaches past it for more.
@immutable
class RewardCardData {
  const RewardCardData({
    required this.imageUrl,
    required this.title,
    required this.priceLabel,
    required this.pointsCost,
    required this.buttonText,
    required this.onPressed,
  });

  final String imageUrl;
  final String title;
  final String priceLabel;
  final int pointsCost;

  /// The redeem action's label — "Redeem" in the store, "Use" on an
  /// already-earned reward.
  final String buttonText;
  final VoidCallback onPressed;
}
