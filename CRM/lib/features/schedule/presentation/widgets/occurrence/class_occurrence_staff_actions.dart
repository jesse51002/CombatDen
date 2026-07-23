import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// The front-desk single-occurrence lifecycle actions on the occurrence screen:
/// **Move to another day** (same time) and **Cancel this class**. Shown for the
/// staff (front-desk) role, whose read-only detail panel carries no action row
/// — owner/admin instead get the full instructor/capacity/date override form
/// (`ClassOccurrenceReadOnlyDetails` + `ClassOccurrenceOverrideSection`) and
/// never see this reduced block. Both actions run through the DEDICATED staff
/// backend endpoints (front desk is allowed to call them; the owner/admin
/// `exceptions/instance` override is not open to front desk).
///
/// This is a pure affordance: it only fires the callbacks. Each callback owns
/// its own confirm/pick + processing → success/error terminal state on the
/// screen, so a cancelled occurrence never renders this block (the caller gates
/// it off).
class ClassOccurrenceStaffActions extends StatelessWidget {
  final VoidCallback onMoveDay;
  final VoidCallback onCancel;

  const ClassOccurrenceStaffActions({
    super.key,
    required this.onMoveDay,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Change this day',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingMedium,
        children: [
          Text(
            'Move this one class to another day (it keeps the same time) or '
            'cancel it. Other dates are not affected.',
            style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          ),
          Row(
            spacing: DesignConstants.spacingLarge,
            children: [
              AppOutlineButton(
                text: 'Move to another day',
                onPressed: onMoveDay,
              ),
              AppOutlineButton(
                text: 'Cancel this class',
                onPressed: onCancel,
                borderColor: DesignConstants.badRed,
                textColor: DesignConstants.badRed,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
