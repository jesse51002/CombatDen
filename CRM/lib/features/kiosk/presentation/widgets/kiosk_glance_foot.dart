import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// The glance's system footer (mockup `.glance-foot`): a hairline, the
/// "Back to start in Ns" auto-return countdown over a draining track, and a
/// visible Done button that returns home early. A tap anywhere else on the
/// glance also returns home (wired at the kiosk surface) — this is the explicit
/// affordance. The countdown [secondsLeft] is driven by the cubit's 8s timer.
class KioskGlanceFoot extends StatelessWidget {
  final int secondsLeft;

  const KioskGlanceFoot({super.key, required this.secondsLeft});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        const Hairline(),
        Center(child: _ReturnTimer(secondsLeft: secondsLeft)),
        Center(
          child: AppOutlineButton(
            text: 'Done',
            onPressed: () => context.read<KioskFlowCubit>().goHome(),
          ),
        ),
      ],
    );
  }
}

class _ReturnTimer extends StatelessWidget {
  final int secondsLeft;

  const _ReturnTimer({required this.secondsLeft});

  @override
  Widget build(BuildContext context) {
    final total = kKioskGlanceAutoReturn.inSeconds;
    final fraction = total <= 0 ? 0.0 : (secondsLeft / total).clamp(0.0, 1.0);
    // Match the track width to the label so the bar reads as its underline.
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
