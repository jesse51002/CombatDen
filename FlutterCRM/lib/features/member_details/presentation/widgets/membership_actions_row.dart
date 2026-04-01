import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';

/// Row with Freeze Membership and Cancel Membership
/// buttons.
class MembershipActionsRow extends StatelessWidget {
  const MembershipActionsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical:
            DesignConstants.spacingLarge,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _actionButton(
            context,
            'Freeze Membership',
            onPressed: () => _confirmFreeze(context),
          ),
          const SizedBox(
            width:
                DesignConstants.spacingMedium,
          ),
          _actionButton(
            context,
            'Cancel Membership',
            onPressed: () => _confirmCancel(context),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    BuildContext context,
    String label, {
    VoidCallback? onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: DesignConstants.text,
        side: const BorderSide(
          color: DesignConstants.buttonStroke,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal:
              DesignConstants.spacingLarge,
          vertical:
              DesignConstants.spacingSmall,
        ),
      ),
      child: Text(label, style: DesignConstants.h3),
    );
  }

  Future<void> _confirmFreeze(
    BuildContext context,
  ) async {
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: 'Freeze Membership',
      message:
          'Are you sure you want to freeze this membership?',
      confirmLabel: 'Freeze',
    );
    if (confirmed) {
      // TODO: Dispatch freeze event to BLoC
    }
  }

  Future<void> _confirmCancel(
    BuildContext context,
  ) async {
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: 'Cancel Membership',
      message:
          'Are you sure you want to cancel this membership? This action cannot be undone.',
      confirmLabel: 'Cancel Membership',
    );
    if (confirmed) {
      // TODO: Dispatch cancel event to BLoC
    }
  }
}
