import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:theme_flutter/theme/theme_text.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/dividers/section_divider.dart';

/// Footer with a top divider and the primary "Reserve your spot" CTA.
class ClassReserveFooter extends StatelessWidget {
  const ClassReserveFooter({super.key, required this.onReserve, this.buttonKey});

  final VoidCallback onReserve;

  /// Capture-only: a key on the CTA so the capture harness can centre a tap
  /// pulse exactly on the button. Null in normal app use.
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionDivider(),
        Padding(
          padding: EdgeInsets.all(DesignConstants.paddingBig),
          child: KeyedSubtree(
            key: buttonKey,
            child: AppPrimaryButton(
              text: ThemeText.value(
                CombatDenSlots.reserveCta,
                fallback: 'Reserve your spot',
              ),
              onPressed: onReserve,
              fullWidth: true,
              borderRadius: DesignConstants.radiusBig,
            ),
          ),
        ),
      ],
    );
  }
}
