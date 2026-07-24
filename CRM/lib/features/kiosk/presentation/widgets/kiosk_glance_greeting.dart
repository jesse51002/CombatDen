import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:theme_flutter/theme/animation/scale_reveal.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/kiosk_reveal_timings.dart';

/// The glance's confirmation — a filled green check disc beside ONE
/// kiosk-scale statement naming the class the member is now checked into
/// (mockup `.glance-top`).
///
/// **One line, and it is a fact.** At this instant the member wants to know
/// whether it worked and into what; a congratulatory "Nice one, Marcus." above
/// or below it adds no information and delays the answer, so there is nothing
/// beneath this line. The celebration is the streak and the rewards under it —
/// this part just has to be unambiguous.
///
/// A repeat ([alreadyCheckedIn]) says so, because a same-day re-tap earns
/// nothing and must not read as a fresh check-in. [className] is omitted only
/// when it genuinely isn't known (a state with no picked occurrence), and the
/// line falls back to the bare fact rather than a guess.
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

/// The check mark itself, popping in as the statement fades up beside it — the
/// shared [ScaleReveal] the member app's celebrations already use, so the
/// "it worked" beat lands with a little weight instead of appearing. Flat and
/// immediate under reduced motion.
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
