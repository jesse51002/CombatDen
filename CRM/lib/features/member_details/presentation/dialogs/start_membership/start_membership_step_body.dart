import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant_banner.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_plan_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_review_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_step_indicator.dart';

/// The scrollable body of the Start Membership wizard:
/// the step indicator, the participant banner (past step 0),
/// and the active step. Pure presentation — all state and
/// transitions live in the orchestrator dialog.
class StartMembershipStepBody extends StatelessWidget {
  final StartMembershipStep step;
  final MemberDetailResponse member;
  final MemberRepository repository;
  final StartMembershipParticipant participant;
  final MembershipPlanResponse? plan;
  final bool prorate;
  final bool paidWithCash;
  final MemberMembershipsStartRequest? request;
  final Map<String, String> disabledPlanReasons;
  final Map<String, String> warningPlanReasons;
  final bool participantHasActiveOneTime;
  final bool showParticipantStep;
  final ValueChanged<StartMembershipParticipant>
      onParticipantSelected;
  final ValueChanged<MembershipPlanResponse> onPlanSelected;
  final ValueChanged<bool> onProrateChanged;
  final ValueChanged<bool> onPaidWithCashChanged;

  const StartMembershipStepBody({
    super.key,
    required this.step,
    required this.member,
    required this.repository,
    required this.participant,
    required this.plan,
    required this.prorate,
    required this.paidWithCash,
    required this.request,
    required this.disabledPlanReasons,
    required this.warningPlanReasons,
    required this.participantHasActiveOneTime,
    required this.showParticipantStep,
    required this.onParticipantSelected,
    required this.onPlanSelected,
    required this.onProrateChanged,
    required this.onPaidWithCashChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        StartMembershipStepIndicator(
          step: step,
          showParticipantStep: showParticipantStep,
        ),
        if (step != StartMembershipStep.participant)
          StartMembershipParticipantBanner(
            participant: participant,
          ),
        switch (step) {
          StartMembershipStep.participant =>
            StartMembershipParticipantStep(
              member: member,
              selectedMemberId: participant.memberId,
              onSelected: onParticipantSelected,
            ),
          StartMembershipStep.plan =>
            StartMembershipPlanStep(
              repository: repository,
              gymId: member.gymId,
              selected: plan,
              onSelected: onPlanSelected,
              disabledPlanReasons: disabledPlanReasons,
              warningPlanReasons: warningPlanReasons,
              participantHasActiveOneTime:
                  participantHasActiveOneTime,
            ),
          StartMembershipStep.review =>
            StartMembershipReviewStep(
              repository: repository,
              request: request,
              planType: plan?.planType ?? PlanType.unknown,
              prorate: prorate,
              paidWithCash: paidWithCash,
              onProrateChanged: onProrateChanged,
              onPaidWithCashChanged: onPaidWithCashChanged,
            ),
        },
      ],
    );
  }
}
