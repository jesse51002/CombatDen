import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// A download-action button that flips to a disabled in-flight state — a small
/// spinner ahead of a "Preparing…" [busyLabel] — while a download runs, so an
/// action never resolves to a silently vanishing spinner. [primary] draws the
/// sapphire gradient CTA (the section's single primary), otherwise the neutral
/// outline button. Idle shows [label] and is tappable via [onPressed].
class ReportActionButton extends StatelessWidget {
  final String label;
  final String busyLabel;
  final bool primary;
  final bool busy;
  final VoidCallback onPressed;

  const ReportActionButton({
    super.key,
    required this.label,
    required this.busyLabel,
    required this.busy,
    required this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    // The in-button spinner contrasts with the button fill: near-white ink on
    // the gradient CTA, the standard text colour on the outline button.
    final spinnerColor =
        primary ? DesignConstants.onAccent : DesignConstants.text;
    final icon = busy ? _ButtonSpinner(color: spinnerColor) : null;
    final text = busy ? busyLabel : label;
    final onTap = busy ? null : onPressed;

    return primary
        ? AppPrimaryButton(text: text, icon: icon, onPressed: onTap)
        : AppOutlineButton(text: text, icon: icon, onPressed: onTap);
  }
}

/// A small determinate-width spinner sized to sit inline in a button label,
/// tinted to [color] to match the button's foreground (mirrors the loading
/// indicator [AppPrimaryButton] draws internally).
class _ButtonSpinner extends StatelessWidget {
  final Color color;

  const _ButtonSpinner({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DesignConstants.iconSizeSmall,
      width: DesignConstants.iconSizeSmall,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}
