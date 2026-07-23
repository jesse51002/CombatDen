import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/shared/widgets/progress_arc.dart';

/// Thousand-separated points (2150 -> "2,150"), shared by every glance number.
final NumberFormat _points = NumberFormat.decimalPattern();

String formatKioskPoints(int n) => _points.format(n);

/// The reward image's 3:2 ratio (mirrors the member app reward card's hero).
const double _kRewardImageAspect = 1.5;

/// The status ring's stroke as a fraction of its box — a ~4px stroke at the
/// small trailing 24px ring size.
const double _kRingStrokeRatio = 0.16;

/// One reward as the glance's image-first tile — a 1:1 rebuild of the member
/// app reward card's anatomy (`RewardImageHero` + `RewardPriceTag` + the fixed
/// two-line title slot + a brand points line) against `DesignConstants`, with
/// the store card's Redeem CTA replaced by the kiosk STATUS row (mockup
/// `.reward` / `.reward.ready`):
///   * affordable (`balance >= cost`): "{cost} pts" + a filled ready disc, and
///     the tile gains the brand accent border.
///   * in progress (`balance < cost`): "{balance} / {cost}" + a progress ring.
///   * balance unknown (billing fetch failed): cost only, no indicator.
class KioskRewardTile extends StatelessWidget {
  final RewardResponse reward;

  /// The member's points balance, or null when the billing fetch failed — the
  /// tile then shows cost only (no ready/progress indicator).
  final int? balance;

  const KioskRewardTile({
    super.key,
    required this.reward,
    required this.balance,
  });

  bool get _ready => balance != null && balance! >= reward.pointCost;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: DesignConstants.surface,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        border: Border.all(
          color: _ready ? DesignConstants.primaryColor : DesignConstants.line,
          width: _ready
              ? DesignConstants.buttonBorder
              : DesignConstants.dividerThickness,
        ),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RewardImageHero(
            imageUrl: reward.imageUrl,
            priceLabel: reward.priceLabel,
          ),
          Padding(
            padding: const EdgeInsets.all(DesignConstants.spacingMedium),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingMedium,
              children: [
                SizedBox(
                  height: DesignConstants.rewardCardTitleHeight,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Text(
                      reward.title,
                      style: DesignConstants.h2,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                _RewardStatus(
                  cost: reward.pointCost,
                  balance: balance,
                  ready: _ready,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 3:2 cover image with the brand-filled price tag pinned top-right.
class _RewardImageHero extends StatelessWidget {
  final String? imageUrl;
  final String? priceLabel;

  const _RewardImageHero({required this.imageUrl, required this.priceLabel});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _kRewardImageAspect,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null && imageUrl!.isNotEmpty)
            Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const _ImagePlaceholder(),
            )
          else
            const _ImagePlaceholder(),
          if (priceLabel != null && priceLabel!.isNotEmpty)
            Positioned(
              top: DesignConstants.spacingMedium,
              right: DesignConstants.spacingMedium,
              child: _PriceTag(label: priceLabel!),
            ),
        ],
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DesignConstants.backgroundAlt,
      child: Center(
        child: Icon(
          Symbols.image_sharp,
          size: DesignConstants.iconSizeBig,
          color: DesignConstants.text3rd,
          weight: DesignConstants.iconWeight,
        ),
      ),
    );
  }
}

class _PriceTag extends StatelessWidget {
  final String label;

  const _PriceTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingTiny,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Text(
        label,
        style: DesignConstants.pSmallBold.copyWith(
          color: DesignConstants.onAccent,
        ),
      ),
    );
  }
}

/// The kiosk status row — the points line with its trailing indicator stacked
/// below it (a fixed position across tiles), mockup `.reward-status`.
class _RewardStatus extends StatelessWidget {
  final int cost;
  final int? balance;
  final bool ready;

  const _RewardStatus({
    required this.cost,
    required this.balance,
    required this.ready,
  });

  @override
  Widget build(BuildContext context) {
    final knownAndShort = balance != null && !ready;
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        if (knownAndShort)
          _FractionText(balance: balance!, cost: cost)
        else
          Text(
            '${formatKioskPoints(cost)} pts',
            style: DesignConstants.h2Bold.copyWith(
              color: DesignConstants.primaryColor,
            ),
            textAlign: TextAlign.center,
          ),
        if (ready)
          const _ReadyDisc()
        else if (knownAndShort)
          _ProgressRing(
            progress: cost <= 0 ? 1 : (balance! / cost).clamp(0.0, 1.0),
          ),
      ],
    );
  }
}

/// "{balance} / {cost}" — numerator bold, both brand-coloured (mockup `.frac`).
class _FractionText extends StatelessWidget {
  final int balance;
  final int cost;

  const _FractionText({required this.balance, required this.cost});

  @override
  Widget build(BuildContext context) {
    final base = DesignConstants.h3.copyWith(color: DesignConstants.primaryColor);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(
            text: formatKioskPoints(balance),
            style: base.copyWith(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: ' / ${formatKioskPoints(cost)}'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _ReadyDisc extends StatelessWidget {
  const _ReadyDisc();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: DesignConstants.iconSizeLarge,
      height: DesignConstants.iconSizeLarge,
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Symbols.check_sharp,
        size: DesignConstants.iconSizeTiny,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.onAccent,
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  final double progress;

  const _ProgressRing({required this.progress});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: DesignConstants.iconSizeLarge,
      height: DesignConstants.iconSizeLarge,
      child: ProgressArc(
        progress: progress,
        progressColor: DesignConstants.primaryColor,
        trackColor: DesignConstants.line,
        strokeRatio: _kRingStrokeRatio,
      ),
    );
  }
}
