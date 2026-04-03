import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/presentation/widgets/membership_carousel/freeze_cancel_modal.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// Row with Freeze Membership and Cancel Membership
/// buttons that open the shared Freeze/Cancel modal.
class MembershipActionsRow extends StatelessWidget {
  final List<MembershipInfo> memberships;

  const MembershipActionsRow({
    super.key,
    this.memberships = const [],
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: DesignConstants.spacingLarge,
        ),
        child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: DesignConstants.spacingMedium,
        runSpacing: DesignConstants.spacingMedium,
        children: [
          _actionButton(
            context,
            'Freeze Membership',
            onPressed: () => FreezeCancelModal.show(
              context: context,
              memberships: memberships,
              initialTab: 'freeze',
            ),
          ),
          _actionButton(
            context,
            'Cancel Membership',
            onPressed: () => FreezeCancelModal.show(
              context: context,
              memberships: memberships,
              initialTab: 'cancel',
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(
    BuildContext context,
    String label, {
    VoidCallback? onPressed,
  }) {
    return AppOutlineButton(
      text: label,
      onPressed: onPressed,
      borderRadius: DesignConstants.radiusSmall,
      textStyle: DesignConstants.h3,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingLarge,
        vertical: DesignConstants.spacingSmall,
      ),
    );
  }
}
