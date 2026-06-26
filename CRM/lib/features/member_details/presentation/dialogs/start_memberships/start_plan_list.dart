import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/membership_draft.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_plan_check_tile.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// The gym's purchasable plans as a checkbox list — the
/// plans step's content group below "Already has".
class StartPlanList extends StatelessWidget {
  final Future<List<MembershipPlanResponse>> plansFuture;
  final MembershipDraft? Function(String planId) draftFor;
  final Map<String, String> disabledPlanReasons;
  final ValueChanged<MembershipPlanResponse> onToggle;
  final void Function(String planId, int count)
      onCountChanged;

  const StartPlanList({
    super.key,
    required this.plansFuture,
    required this.draftFor,
    required this.disabledPlanReasons,
    required this.onToggle,
    required this.onCountChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MembershipPlanResponse>>(
      future: plansFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState !=
            ConnectionState.done) {
          return const SizedBox(
            height: DesignConstants.dialogProcessingHeight,
            child: Center(child: AppSpinner()),
          );
        }
        if (snapshot.hasError) {
          return Text(
            'Couldn’t load plans. Please try again.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          );
        }
        final plans = (snapshot.data ?? const [])
            .where((p) => p.activePrice != null)
            .toList();
        if (plans.isEmpty) {
          return Text(
            'This gym has no purchasable plans yet.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          );
        }
        return Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingMedium,
          children: plans.map((p) {
            final draft = draftFor(p.planId);
            return StartPlanCheckTile(
              plan: p,
              draft: draft,
              disabledReason:
                  disabledPlanReasons[p.planId],
              onToggle: () => onToggle(p),
              onCountChanged: (c) =>
                  onCountChanged(p.planId, c),
            );
          }).toList(),
        );
      },
    );
  }
}
