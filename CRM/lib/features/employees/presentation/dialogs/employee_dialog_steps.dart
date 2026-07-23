import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// The employee dialogs' shared **processing** step — the charge-card
/// `_ChargeProcessing` shape: an [AppSpinner] + a label in a fixed
/// `dialogProcessingHeight` box, so the surface never jumps size while a
/// mutation runs.
class EmployeeDialogProcessing extends StatelessWidget {
  final String label;

  const EmployeeDialogProcessing({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DesignConstants.dialogProcessingHeight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [
            const AppSpinner(),
            Text(
              label,
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The employee dialogs' shared **success** step — the `ChargeCardSuccessView`
/// shape: a green check, an `h2` title, and a `p`/`text2nd` detail line.
class EmployeeDialogSuccess extends StatelessWidget {
  final String title;
  final String detail;

  const EmployeeDialogSuccess({
    super.key,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        Icon(
          Symbols.check_circle_sharp,
          weight: DesignConstants.iconWeight,
          size: DesignConstants.iconSizeBig,
          color: DesignConstants.goodGreen,
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(title, style: DesignConstants.h2),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
