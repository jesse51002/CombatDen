import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Step 1 — pick a membership plan. Plans without an active
/// price are hidden; selecting one implicitly chooses its
/// active price. Plans the participant already holds are
/// disabled with a reason; soft warnings stay selectable.
class StartMembershipPlanStep extends StatefulWidget {
  final MemberRepository repository;
  final String gymId;
  final MembershipPlanResponse? selected;
  final ValueChanged<MembershipPlanResponse> onSelected;
  final Map<String, String> disabledPlanReasons;
  final Map<String, String> warningPlanReasons;
  final bool participantHasActiveOneTime;

  const StartMembershipPlanStep({
    super.key,
    required this.repository,
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
    _future =
        widget.repository.listMembershipPlans(widget.gymId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MembershipPlanResponse>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState !=
            ConnectionState.done) {
          return const SizedBox(
            height: 160,
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
            ? DesignConstants.primaryColor10
            : DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(
          color: selected && !disabled
              ? DesignConstants.primaryColor
              : DesignConstants.divider,
          width: selected && !disabled ? 2 : 1,
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
