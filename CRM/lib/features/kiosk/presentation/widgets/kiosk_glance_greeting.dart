import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The glance's celebratory header — a filled green check disc beside a
/// kiosk-scale greeting, centered (mockup `.glance-top`). A fresh check-in
/// reads "Nice one, {FirstName}."; a repeat ([alreadyCheckedIn]) softens to
/// "You're already checked in for today, {FirstName}." so a same-day re-tap
/// (which earns nothing) doesn't read as a fresh celebration. The greeting is
/// [firstName] already reduced to the first name by the caller.
class KioskGlanceGreeting extends StatelessWidget {
  final String firstName;
  final bool alreadyCheckedIn;

  const KioskGlanceGreeting({
    super.key,
    required this.firstName,
    this.alreadyCheckedIn = false,
  });

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
            alreadyCheckedIn
                ? 'You\'re already checked in for today, $firstName.'
                : 'Nice one, $firstName.',
            style: DesignConstants.kioskDisplay,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _CheckDisc extends StatelessWidget {
  const _CheckDisc();

  @override
  Widget build(BuildContext context) {
    return Container(
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
  }
}
