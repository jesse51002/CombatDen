import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The "Back to start in Ns" auto-return countdown over a thin draining track
/// — shared by the glance's 10-second footer and the "Get the app" modal's
/// 60-second one. [total] is the full duration in seconds (it sets the drain
/// fraction); [secondsLeft] is the live countdown.
class KioskReturnTimer extends StatelessWidget {
  final int total;
  final int secondsLeft;

  const KioskReturnTimer({
    super.key,
    required this.total,
    required this.secondsLeft,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = total <= 0 ? 0.0 : (secondsLeft / total).clamp(0.0, 1.0);
    return IntrinsicWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingMedium,
        children: [
          Text(
            'Back to start in ${secondsLeft}s',
            style: DesignConstants.kioskCaption.copyWith(
              color: DesignConstants.text2nd,
            ),
            textAlign: TextAlign.center,
          ),
          _DrainBar(fraction: fraction),
        ],
      ),
    );
  }
}

/// A thin track that drains left-to-right over the countdown. The fill stays
/// on [DesignConstants.text3rd]: it carries no words, so the kiosk's AA text
/// floor doesn't apply and the quieter tint keeps it reading as the label's
/// underline rather than a second line of ink.
class _DrainBar extends StatelessWidget {
  final double fraction;

  const _DrainBar({required this.fraction});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Container(
        height: DesignConstants.progressBarThickness,
        color: DesignConstants.line,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 1, end: fraction),
          duration: const Duration(seconds: 1),
          builder: (context, value, _) {
            return FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: ColoredBox(color: DesignConstants.text3rd),
            );
          },
        ),
      ),
    );
  }
}
