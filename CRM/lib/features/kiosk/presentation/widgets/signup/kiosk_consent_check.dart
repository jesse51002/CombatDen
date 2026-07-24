import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The kiosk's checkbox — a big, unmissable tick box beside a line of ink.
///
/// Built to the kiosk BUTTON vocabulary rather than Material's `Checkbox`:
/// [DesignConstants.radiusSmall] corners, the resting hairline, and the
/// sapphire fill + lift the primary tier uses when it is on. A stock checkbox
/// is sized for a mouse; this one has to be found and hit with a thumb from
/// standing distance, so the whole row is the target, not just the box.
///
/// Used by the waiver step's consent line and by every roster row's "getting a
/// membership" check.
class KioskConsentCheck extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  /// The line beside the box. It is the label AND the tap target.
  final String label;

  /// An optional quieter second line under [label] (a waiver's "you are
  /// signing this electronically" note).
  final String? note;

  const KioskConsentCheck({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final second = note;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          _Box(on: value),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingSmall,
              children: [
                Text(label, style: DesignConstants.kioskLabel),
                if (second != null)
                  Text(
                    second,
                    style: DesignConstants.kioskCaption.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  final bool on;

  const _Box({required this.on});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: DesignConstants.iconSizeBig,
      height: DesignConstants.iconSizeBig,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? DesignConstants.primaryColor : DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        border: Border.all(
          color: on ? DesignConstants.primaryColor : DesignConstants.text,
          width: DesignConstants.buttonBorder,
        ),
        boxShadow:
            on ? DesignConstants.buttonShadow : DesignConstants.controlShadow,
      ),
      child: on
          ? Icon(
              Symbols.check_sharp,
              size: DesignConstants.iconSizeSmall,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.onAccent,
            )
          : null,
    );
  }
}
