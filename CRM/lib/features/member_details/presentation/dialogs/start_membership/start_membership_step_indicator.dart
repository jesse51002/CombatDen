import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_step.dart';

/// Horizontal progress bar across the wizard steps. The
/// participant segment is hidden when the member has no
/// linked accounts (the flow opens on the plan step).
class StartMembershipStepIndicator extends StatelessWidget {
  final StartMembershipStep step;
  final bool showParticipantStep;

  const StartMembershipStepIndicator({
    super.key,
    required this.step,
    required this.showParticipantStep,
  });

  @override
  Widget build(BuildContext context) {
    final visibleSteps = <StartMembershipStep>[
      if (showParticipantStep)
        StartMembershipStep.participant,
      StartMembershipStep.plan,
      StartMembershipStep.discounts,
      StartMembershipStep.review,
    ];
    final index = visibleSteps.indexOf(step);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      spacing: DesignConstants.spacingSmall,
      children: List.generate(visibleSteps.length, (i) {
        final active = i == index;
        final done = i < index;
        final color = active
            ? DesignConstants.primaryColor
            : done
                ? DesignConstants.goodGreen
                : DesignConstants.text3rd;
        return Expanded(
          child: Column(
            spacing: DesignConstants.spacingTiny,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius:
                      BorderRadius.circular(2),
                ),
              ),
              Text(
                _label(visibleSteps[i]),
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

  String _label(StartMembershipStep s) {
    switch (s) {
      case StartMembershipStep.participant:
        return 'Person';
      case StartMembershipStep.plan:
        return 'Plan';
      case StartMembershipStep.discounts:
        return 'Discounts';
      case StartMembershipStep.review:
        return 'Review';
    }
  }
}
