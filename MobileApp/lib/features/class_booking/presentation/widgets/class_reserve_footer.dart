import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:theme_flutter/theme/theme_text.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/dividers/section_divider.dart';

/// Where a layout puts the one reserve action.
///
/// The screen commits in exactly one place. These values move that
/// place; none of them adds a second one.
enum ClassReservePosition {
  /// Pinned under the scrolling body, rule above. Ships today.
  pinned,

  /// At the top of a sheet, rule below — the action arrives on the way
  /// down instead of at the end of a scroll.
  sheetTop,

  /// In the content flow, at the end of it. Carries no side padding
  /// because the content column already supplies it.
  inline,
}

/// The primary "Reserve your spot" CTA and its separating rule.
class ClassReserveFooter extends StatelessWidget {
  const ClassReserveFooter({
    super.key,
    required this.onReserve,
    this.buttonKey,
    this.position = ClassReservePosition.pinned,
  });

  final VoidCallback onReserve;
  final ClassReservePosition position;

  /// Capture-only: a key on the CTA so the capture harness can centre a tap
  /// pulse exactly on the button. Null in normal app use.
  final Key? buttonKey;

  EdgeInsets get _padding => switch (position) {
    ClassReservePosition.pinned => EdgeInsets.all(DesignConstants.paddingBig),
    ClassReservePosition.sheetTop => EdgeInsets.symmetric(
      horizontal: DesignConstants.paddingBig,
      vertical: DesignConstants.spacingLarge,
    ),
    ClassReservePosition.inline => EdgeInsets.symmetric(
      vertical: DesignConstants.spacingLarge,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final action = Padding(
      padding: _padding,
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
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: position == ClassReservePosition.sheetTop
          ? [action, const SectionDivider()]
          : [const SectionDivider(), action],
    );
  }
}
