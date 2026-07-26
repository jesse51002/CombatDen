import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// The kiosk's checkbox — a big tick box beside a line of ink, built to the
/// kiosk BUTTON vocabulary rather than Material's `Checkbox`: a stock checkbox
/// is sized for a mouse, and this has to be found and hit with a thumb from
/// standing distance, so the whole row is the target.
class FlowConsentCheck extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  /// The line beside the box. It is the label AND the tap target.
  final String label;

  /// An optional quieter second line under [label].
  final String? note;

  const FlowConsentCheck({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
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
                Text(label, style: scale.label),
                if (second != null)
                  Text(
                    second,
                    style: scale.caption.copyWith(
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
