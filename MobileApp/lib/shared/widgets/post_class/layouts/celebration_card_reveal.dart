import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/post_class/celebration_data.dart';
import 'package:mobile_app/shared/widgets/post_class/parts/celebration_close.dart';
import 'package:mobile_app/shared/widgets/post_class/parts/celebration_cta.dart';
import 'package:mobile_app/shared/widgets/post_class/parts/celebration_stage.dart';

/// `CelebrationFormat.cardReveal` — the stat as a collectible.
///
/// The whole celebration rides one raised, rounded object floating on
/// the canvas, with the close in the card's own corner and the action on
/// bare canvas beneath it. The most "collectible" of the five and the
/// right pick for a tenant leaning on rewards.
///
/// The card floats on the narrow token and pads on the narrow token, so
/// the stage still gets the full 358pt the shipped value gives it. That
/// is deliberate: the Points count-up reel is a Row that already fills
/// the shipped width, so a card that stole 16pt a side would overflow it.
class CelebrationCardReveal extends StatelessWidget {
  const CelebrationCardReveal({super.key, required this.data});

  final CelebrationData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: DesignConstants.spacingLarge,
        bottom: DesignConstants.spacingBig,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          if (data.header case final header?) _inset(header),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: DesignConstants.spacingMedium,
              ),
              child: _Card(data: data),
            ),
          ),
          _inset(CelebrationCta(data: data)),
        ],
      ),
    );
  }

  /// Screen-edge containment for the slots that sit off the card.
  Widget _inset(Widget child) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: DesignConstants.screenHorizontalPadding,
    ),
    child: child,
  );
}

/// The raised surface. Deliberately a `DecoratedBox` and not a clipping
/// `Container`: the Wins card's sparkle burst spills a few points past
/// the corners, which is the only surviving echo of the doc's
/// "illustration breaking over the card's top edge".
class _Card extends StatelessWidget {
  const _Card({required this.data});

  final CelebrationData data;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: DesignConstants.spacingMedium,
              vertical: DesignConstants.spacingLarge,
            ),
            child: CelebrationStage(data: data),
          ),
          if (data.onClose case final close?)
            Positioned(
              top: DesignConstants.spacingLarge,
              right: DesignConstants.spacingLarge,
              child: CelebrationClose(onClose: close),
            ),
        ],
      ),
    );
  }
}
