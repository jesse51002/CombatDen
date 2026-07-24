import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';

/// One roster row's details readout — **a state readout, not an opt-in.**
///
/// Every person on the roster has already been shown their own details screen
/// (the payer at step 2, each payee as the second screen of adding them), so
/// this is the answer to "did anything come of it"; tapping it returns to that
/// same screen to finish or correct.
///
/// Two states and no third: the good-hue tick when something is on file, a
/// quiet hairline when the screen was skipped. **"None yet" is a fact, not a
/// nag** — no red, no count of what is missing, no second ask. A payee matched
/// to an existing member reads "Details on file": their record already has
/// them, and a shared screen is not where they get printed.
class KioskDetChip extends StatelessWidget {
  final KioskSignupDetailsStatus status;

  /// This person was matched to an existing member, so the gym already holds
  /// their details whatever was typed here.
  final bool onFile;

  final VoidCallback onTap;

  const KioskDetChip({
    super.key,
    required this.status,
    required this.onFile,
    required this.onTap,
  });

  bool get _done => onFile || status != KioskSignupDetailsStatus.none;

  String get _label {
    if (onFile) return 'Details on file';
    return status == KioskSignupDetailsStatus.none
        ? 'None yet'
        : 'Details added';
  }

  @override
  Widget build(BuildContext context) {
    final done = _done;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        decoration: BoxDecoration(
          color: done
              ? DesignConstants.goodGreen.withValues(alpha: 0.14)
              : DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          border: Border.all(
            color: done ? DesignConstants.goodGreen : DesignConstants.line,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingSmall,
          children: [
            Icon(
              done ? Symbols.check_sharp : Symbols.edit_sharp,
              size: DesignConstants.iconSizeSmall,
              weight: DesignConstants.iconWeight,
              color: done ? DesignConstants.goodGreen : DesignConstants.text2nd,
            ),
            Text(
              _label,
              style: DesignConstants.kioskCaption.copyWith(
                color: done ? DesignConstants.goodGreen : DesignConstants.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
