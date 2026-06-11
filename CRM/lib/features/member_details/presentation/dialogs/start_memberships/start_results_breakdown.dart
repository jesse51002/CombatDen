import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_result_row.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// The landed response's per-membership breakdown: one row
/// per result, the two-charges note when the run split, and
/// the "retry failed" affordance when any item failed.
class StartResultsBreakdown extends StatelessWidget {
  final MemberMembershipsStartResponse result;
  final Map<String, String> memberNames;
  final Map<String, String> planNames;
  final VoidCallback onRetryFailed;
  final ValueChanged<String> onViewMember;

  const StartResultsBreakdown({
    super.key,
    required this.result,
    required this.memberNames,
    required this.planNames,
    required this.onRetryFailed,
    required this.onViewMember,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        if (result.multipleCharges)
          Container(
            padding: const EdgeInsets.all(
              DesignConstants.paddingSmall,
            ),
            decoration: BoxDecoration(
              color: DesignConstants.backgroundColor,
              borderRadius: BorderRadius.circular(
                DesignConstants.radiusSmall,
              ),
              border: Border.all(
                color: DesignConstants.divider,
              ),
            ),
            child: Text(
              'Two separate charges were made: one for '
              'the one-time purchases and one for the '
              'recurring memberships.',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingMedium,
          children: result.results
              .map(
                (r) => StartResultRow(
                  item: r,
                  memberName:
                      memberNames[r.memberId] ??
                          'Member',
                  planName:
                      planNames[r.planId] ?? 'Plan',
                  onView: r.isCreated
                      ? () =>
                          onViewMember(r.memberId)
                      : null,
                ),
              )
              .toList(),
        ),
        if (result.hasFailures)
          Align(
            alignment: Alignment.centerLeft,
            child: AppOutlineButton(
              text: 'Retry the failed memberships',
              borderRadius: DesignConstants.radiusSmall,
              onPressed: onRetryFailed,
            ),
          ),
      ],
    );
  }
}
