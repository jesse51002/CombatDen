import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The white lifted panel a signup step's fields sit on — the same object
/// card the rest of the app uses (surface fill,
/// [DesignConstants.radiusCard] corners, hairline, `cardShadow`), capped at a
/// readable measure and centred on the wide kiosk stage.
///
/// One panel per step. A step that needs internal grouping uses
/// [KioskSignupDetailGroup] inside it rather than a second panel — two panels
/// read as two unrelated forms.
class KioskSignupFormPanel extends StatelessWidget {
  final List<Widget> children;

  const KioskSignupFormPanel({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: DesignConstants.kioskFormMeasure,
        ),
        child: Container(
          padding: const EdgeInsets.all(DesignConstants.paddingBig),
          decoration: BoxDecoration(
            color: DesignConstants.surface,
            borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
            border: Border.all(color: DesignConstants.line),
            boxShadow: DesignConstants.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingLarge,
            children: children,
          ),
        ),
      ),
    );
  }
}
