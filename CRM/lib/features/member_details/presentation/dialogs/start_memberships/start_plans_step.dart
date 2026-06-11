import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/membership_draft.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/plan_count_stepper.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_labels.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Step 3 (per member) — checkbox list of the gym's plans
/// for the member currently being configured. Plans without
/// an active price are hidden; a checked one_time / trial
/// plan grows a count stepper that multiplies the displayed
/// class allowance. Plans the member already actively holds
/// are disabled with the reason.
class StartPlansStep extends StatelessWidget {
  final StartMembershipParticipant member;
  final Future<List<MembershipPlanResponse>> plansFuture;
  final List<MembershipDraft> drafts;
  final Map<String, String> disabledPlanReasons;
  final ValueChanged<MembershipPlanResponse> onToggle;
  final void Function(String planId, int count)
      onCountChanged;

  const StartPlansStep({
    super.key,
    required this.member,
    required this.plansFuture,
    required this.drafts,
    required this.disabledPlanReasons,
    required this.onToggle,
    required this.onCountChanged,
  });

  MembershipDraft? _draftFor(String planId) {
    for (final d in drafts) {
      if (d.plan.planId == planId) return d;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          'Memberships for ${member.name}',
          style: DesignConstants.h3,
        ),
        FutureBuilder<List<MembershipPlanResponse>>(
          future: plansFuture,
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
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingSmall,
              children: plans.map((p) {
                final draft = _draftFor(p.planId);
                return _PlanCheckTile(
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
        ),
      ],
    );
  }
}

class _PlanCheckTile extends StatelessWidget {
  final MembershipPlanResponse plan;

  /// Non-null when the plan is checked.
  final MembershipDraft? draft;
  final String? disabledReason;
  final VoidCallback onToggle;
  final ValueChanged<int> onCountChanged;

  const _PlanCheckTile({
    required this.plan,
    required this.draft,
    required this.disabledReason,
    required this.onToggle,
    required this.onCountChanged,
  });

  bool get _selected => draft != null;

  bool get _steppable =>
      plan.planType == PlanType.oneTime ||
      plan.planType == PlanType.trial;

  @override
  Widget build(BuildContext context) {
    final disabled = disabledReason != null;
    final body = Container(
      padding: const EdgeInsets.all(
        DesignConstants.spacingMedium,
      ),
      decoration: BoxDecoration(
        color: _selected && !disabled
            ? DesignConstants.primaryColor10
            : DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(
          color: _selected && !disabled
              ? DesignConstants.primaryColor
              : DesignConstants.divider,
          width: _selected && !disabled ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingSmall,
        children: [
          Row(
            spacing: DesignConstants.spacingMedium,
            children: [
              Icon(
                _selected && !disabled
                    ? Symbols.check_box_sharp
                    : Symbols
                        .check_box_outline_blank_sharp,
                weight: DesignConstants.iconWeight,
                size: DesignConstants.iconSizeLarge,
                color: _selected && !disabled
                    ? DesignConstants.primaryColor
                    : DesignConstants.text2nd,
              ),
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
                      '${plan.planType.displayLabel} · '
                      '${planAllowanceLabel(
                        plan,
                        count: draft?.count ?? 1,
                      )}',
                      style: DesignConstants.pSmall
                          .copyWith(
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
          if (_selected && !disabled && _steppable)
            Row(
              spacing: DesignConstants.spacingMedium,
              children: [
                Text(
                  'Quantity',
                  style:
                      DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
                PlanCountStepper(
                  count: draft!.count,
                  onChanged: onCountChanged,
                ),
              ],
            ),
        ],
      ),
    );
    final wrapped =
        disabled ? Opacity(opacity: 0.6, child: body) : body;
    return InkWell(
      onTap: disabled ? null : onToggle,
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusSmall,
      ),
      child: wrapped,
    );
  }
}
