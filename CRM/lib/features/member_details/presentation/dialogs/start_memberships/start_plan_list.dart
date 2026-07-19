import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/membership_draft.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_plan_card.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// The gym's purchasable plans as a two-column grid of image-led product
/// cards — the plans step's content group below "Already has". Cards are laid
/// out as non-scrolling rows of two so the grid measures naturally inside the
/// step's own scroll view; an odd trailing card keeps its half-width column.
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
        return _grid(plans);
      },
    );
  }

  Widget _grid(List<MembershipPlanResponse> plans) {
    final rows = <Widget>[];
    for (var i = 0; i < plans.length; i += 2) {
      final left = plans[i];
      final right = (i + 1 < plans.length) ? plans[i + 1] : null;
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingMedium,
        children: [
          Expanded(child: _card(left)),
          Expanded(
            child: right == null
                ? const SizedBox.shrink()
                : _card(right),
          ),
        ],
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: rows,
    );
  }

  Widget _card(MembershipPlanResponse plan) {
    return StartPlanCard(
      plan: plan,
      draft: draftFor(plan.planId),
      disabledReason: disabledPlanReasons[plan.planId],
      onToggle: () => onToggle(plan),
      onCountChanged: (count) => onCountChanged(plan.planId, count),
    );
  }
}
