import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_membership_step.dart';

/// Horizontal two-segment progress bar for the cancel wizard.
/// The active segment is red (this is a destructive flow),
/// completed segments green, pending segments muted.
class CancelStepIndicator extends StatelessWidget {
  final CancelMembershipStep step;

  const CancelStepIndicator({super.key, required this.step});

  @override
  Widget build(BuildContext context) {
    const labels = ['Person', 'Memberships'];
    final index = CancelMembershipStep.values.indexOf(step);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      spacing: DesignConstants.spacingSmall,
      children: List.generate(labels.length, (i) {
        final active = i == index;
        final done = i < index;
        final color = active
            ? DesignConstants.badRed
            : done
                ? DesignConstants.goodGreen
                : DesignConstants.text3rd;
        return Expanded(
          child: Column(
            spacing: DesignConstants.spacingTiny,
            children: [
              Container(
                height: DesignConstants.spacingSmall,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(
                    DesignConstants.spacingTiny,
                  ),
                ),
              ),
              Text(
                labels[i],
                style: DesignConstants.pSmall.copyWith(
                  color: color,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
