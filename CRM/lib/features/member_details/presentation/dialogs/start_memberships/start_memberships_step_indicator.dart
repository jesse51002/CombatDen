import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_step.dart';

/// Horizontal progress bar across the wizard's seven steps.
class StartMembershipsStepIndicator
    extends StatelessWidget {
  final StartMembershipsStep step;

  const StartMembershipsStepIndicator({
    super.key,
    required this.step,
  });

  @override
  Widget build(BuildContext context) {
    final index =
        StartMembershipsStep.values.indexOf(step);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      spacing: DesignConstants.spacingSmall,
      children: List.generate(
        StartMembershipsStep.values.length,
        (i) {
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
                  _label(StartMembershipsStep.values[i]),
                  style:
                      DesignConstants.pSmall.copyWith(
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _label(StartMembershipsStep s) {
    switch (s) {
      case StartMembershipsStep.payer:
        return 'Payer';
      case StartMembershipsStep.members:
        return 'Who';
      case StartMembershipsStep.plans:
        return 'Plans';
      case StartMembershipsStep.discounts:
        return 'Deals';
      case StartMembershipsStep.preview:
        return 'Preview';
      case StartMembershipsStep.payment:
        return 'Pay';
      case StartMembershipsStep.results:
        return 'Done';
    }
  }
}
