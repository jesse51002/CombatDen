import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:theme_flutter/theme/animation/scale_reveal.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/kiosk_reveal_timings.dart';

/// The glance's confirmation — a filled green check disc beside ONE
/// kiosk-scale statement naming the class the member is now checked into.
///
/// One line, and it is a fact: nothing sits beneath it on purpose. A
/// congratulatory second line adds no information and delays the only answer
/// the member wants; the celebration is the streak and rewards below.
///
/// A repeat ([alreadyCheckedIn]) says so, because a same-day re-tap earns
/// nothing and must not read as a fresh check-in. A null [className] (no
/// picked occurrence) falls back to the bare fact rather than a guess.
class KioskGlanceGreeting extends StatelessWidget {
  final String? className;
  final bool alreadyCheckedIn;

  const KioskGlanceGreeting({
    super.key,
    this.className,
    this.alreadyCheckedIn = false,
  });

  /// The one statement, with or without a known class.
  String get _line {
    final name = className?.trim() ?? '';
    if (name.isEmpty) {
      return alreadyCheckedIn ? 'Already checked in today' : 'Checked in';
    }
    return alreadyCheckedIn
        ? 'Already checked into $name'
        : 'Checked into $name';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        const _CheckDisc(),
        Flexible(
          child: Text(
            _line,
            style: DesignConstants.kioskDisplay,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// The check mark, popping in as the statement fades up beside it — the shared
/// [ScaleReveal] the member app's celebrations use, so the "it worked" beat
/// lands in the same language. Flat and immediate under reduced motion.
class _CheckDisc extends StatelessWidget {
  const _CheckDisc();

  @override
  Widget build(BuildContext context) {
    final disc = Container(
      padding: const EdgeInsets.all(DesignConstants.spacingMedium),
      decoration: BoxDecoration(
        color: DesignConstants.goodGreen,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Symbols.check_sharp,
        size: DesignConstants.iconSizeLarge,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.onFill(DesignConstants.goodGreen),
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return disc;
    return ScaleReveal(
      duration: KioskRevealTimings.confirmationFade,
      child: disc,
    );
  }
}
