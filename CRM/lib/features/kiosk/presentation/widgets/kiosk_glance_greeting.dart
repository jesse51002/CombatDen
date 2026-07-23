import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The glance's celebratory header — a filled green check disc beside a
/// kiosk-scale "Nice one, {FirstName}." greeting, centered (mockup
/// `.glance-top`). The greeting is [firstName] already reduced to the first
/// name by the caller.
class KioskGlanceGreeting extends StatelessWidget {
  final String firstName;

  const KioskGlanceGreeting({super.key, required this.firstName});

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
            'Nice one, $firstName.',
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
