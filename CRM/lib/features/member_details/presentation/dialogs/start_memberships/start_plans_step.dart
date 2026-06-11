import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/membership_draft.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_already_has.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_plan_list.dart';

/// Step 3 (per member) — checkbox list of the gym's plans
/// for the member currently being configured, topped by a
/// compact "Already has" block listing the non-terminal
/// memberships the member currently holds. Plans without
/// an active price are hidden; a checked one_time / trial
/// plan grows a count stepper that multiplies the displayed
/// class allowance. Plans the member already actively holds
/// are disabled with the reason.
class StartPlansStep extends StatelessWidget {
  final StartMembershipParticipant member;
  final Future<List<MembershipPlanResponse>> plansFuture;
  final List<MembershipDraft> drafts;
  final Map<String, String> disabledPlanReasons;

  /// The member's existing non-terminal memberships, from
  /// the wizard's best-effort detail fetch — empty when the
  /// fetch failed (the block just stays hidden).
  final List<MembershipInfo> existingMemberships;
  final ValueChanged<MembershipPlanResponse> onToggle;
  final void Function(String planId, int count)
      onCountChanged;

  const StartPlansStep({
    super.key,
    required this.member,
    required this.plansFuture,
    required this.drafts,
    required this.disabledPlanReasons,
    required this.existingMemberships,
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
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          'Memberships for ${member.name}',
          style: DesignConstants.h2,
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingMedium,
          children: [
            if (existingMemberships.isNotEmpty)
              StartAlreadyHas(
                memberId: member.memberId,
                memberships: existingMemberships,
              ),
            StartPlanList(
              plansFuture: plansFuture,
              draftFor: _draftFor,
              disabledPlanReasons: disabledPlanReasons,
              onToggle: onToggle,
              onCountChanged: onCountChanged,
            ),
          ],
        ),
      ],
    );
  }
}
