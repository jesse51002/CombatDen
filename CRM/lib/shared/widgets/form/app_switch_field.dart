import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Labeled toggle row: a label (+ optional subtitle) on the left, a Material
/// [Switch] on the right. The [Switch] inherits the app's `ColorScheme`
/// (via `AppTheme.current`), so it needs no hardcoded colors.
///
/// Generic/reusable — use anywhere a form needs an explicit opt-in/opt-out
/// toggle rather than inferring state from an empty field (e.g. "no limit"
/// should be a real off-switch, not a blank text field with a fake hint).
class AppSwitchField extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const AppSwitchField({
    super.key,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(label, style: DesignConstants.h2),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
