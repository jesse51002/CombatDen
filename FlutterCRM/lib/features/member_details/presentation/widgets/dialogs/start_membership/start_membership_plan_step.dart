import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';

/// Step 1 — pick a membership plan. Plans without an
/// active price are hidden; selecting one implicitly
/// chooses its active price.
class StartMembershipPlanStep extends StatefulWidget {
  final String gymId;
  final MembershipPlanResponse? selected;
  final ValueChanged<MembershipPlanResponse> onSelected;

  /// Maps `planId` → reason for plans that the participant
  /// is blocked from selecting. Mirrors the DB
  /// `recurring_no_overlapping_daterange` rule per plan.
  final Map<String, String> disabledPlanReasons;

  /// Maps `planId` → soft yellow inline note (still
  /// selectable). Used for "already had this trial in the
  /// past" style hints.
  final Map<String, String> warningPlanReasons;

  /// When true, every one-time plan tile shows a yellow
  /// "Already has an active one-time membership" note.
  /// One-time plans are not blocked — repeat purchases are
  /// allowed, the staff member just gets a heads-up.
  final bool participantHasActiveOneTime;

  const StartMembershipPlanStep({
    super.key,
    required this.gymId,
    required this.selected,
    required this.onSelected,
    this.disabledPlanReasons = const {},
    this.warningPlanReasons = const {},
    this.participantHasActiveOneTime = false,
  });

  @override
  State<StartMembershipPlanStep> createState() =>
      _StartMembershipPlanStepState();
}

class _StartMembershipPlanStepState
    extends State<StartMembershipPlanStep> {
  late Future<List<MembershipPlanResponse>> _future;

  @override
  void initState() {
    super.initState();
    _future = context
        .read<MemberRepository>()
        .listMembershipPlans(widget.gymId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MembershipPlanResponse>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState !=
            ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(
              DesignConstants.spacingLarge,
            ),
            child: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError) {
          return Text(
            'Could not load plans: ${snapshot.error}',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.badRed,
            ),
          );
        }
        final plans = (snapshot.data ?? [])
            .where((p) => p.activePrice != null)
            .toList();
        if (plans.isEmpty) {
          return Text(
            'This gym has no priced plans yet.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingSmall,
          children: plans.map((p) {
            final disabledReason =
                widget.disabledPlanReasons[p.planId];
            final warnings = <String>[
              if (widget.warningPlanReasons[p.planId] !=
                  null)
                widget.warningPlanReasons[p.planId]!,
              if (p.planType == PlanType.oneTime &&
                  widget.participantHasActiveOneTime)
                'Already has this pass active',
            ];
            return _PlanTile(
              plan: p,
              selected:
                  widget.selected?.planId == p.planId,
              disabledReason: disabledReason,
              warnings: warnings,
              onTap: disabledReason == null
                  ? () => widget.onSelected(p)
                  : null,
            );
          }).toList(),
        );
      },
    );
  }

}

class _PlanTile extends StatelessWidget {
  final MembershipPlanResponse plan;
  final bool selected;
  final String? disabledReason;
  final List<String> warnings;
  final VoidCallback? onTap;

  const _PlanTile({
    required this.plan,
    required this.selected,
    required this.disabledReason,
    required this.warnings,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = disabledReason != null;
    final body = Container(
      padding: const EdgeInsets.all(
        DesignConstants.spacingMedium,
      ),
      decoration: BoxDecoration(
        color: selected && !disabled
            ? DesignConstants.primaryColor
                .withValues(alpha: 0.12)
            : DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(
          color: selected && !disabled
              ? DesignConstants.primaryColor
              : DesignConstants.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingSmall,
        children: [
          Row(
            spacing: DesignConstants.spacingMedium,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  spacing: DesignConstants.spacingTiny,
                  children: [
                    Text(
                      plan.planName,
                      style: DesignConstants.h3,
                    ),
                    Text(
                      plan.planType.displayLabel,
                      style:
                          DesignConstants.pSmall.copyWith(
                        color: DesignConstants.text2nd,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                formatMinorUnits(
                  plan.activePrice!.price,
                  currency: 'USD',
                ),
                style: DesignConstants.h2,
              ),
            ],
          ),
          if (disabled)
            Text(
              disabledReason!,
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.goodGreen,
              ),
            ),
          if (!disabled)
            ...warnings.map(
              (w) => Text(
                w,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.okYellow,
                ),
              ),
            ),
        ],
      ),
    );
    final wrapped = disabled
        ? Opacity(opacity: 0.6, child: body)
        : body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusSmall,
      ),
      child: wrapped,
    );
  }
}
