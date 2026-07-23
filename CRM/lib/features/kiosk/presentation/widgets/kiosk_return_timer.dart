import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The "Back to start in Ns" auto-return countdown over a thin draining track —
/// shared by the retention glance's 8-second footer and the "Get the app"
/// modal's 60-second footer (mockup `.timer`). [total] is the full duration in
/// seconds (sets the drain fraction); [secondsLeft] is the live countdown. The
/// track width matches the label so the bar reads as its underline.
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
            style: DesignConstants.pBig.copyWith(
              color: DesignConstants.text3rd,
            ),
            textAlign: TextAlign.center,
          ),
          _DrainBar(fraction: fraction),
        ],
      ),
    );
  }
}

/// A thin track that drains left-to-right over the countdown. Each 1-second
/// step slides smoothly via [TweenAnimationBuilder].
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
