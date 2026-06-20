import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/card_on_file.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_card_capture.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/membership_draft.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_discounts_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_members_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_header.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_step_indicator.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_payer_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_payment_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_plans_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_preview_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_results_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_review_step.dart';

/// The body of the Start Memberships wizard: the step
/// indicator and the persistent payer/current-member
/// context header stay fixed on top as their own zones,
/// and the active step scrolls beneath them at a readable
/// centered measure. Pure presentation — all state and
/// transitions live in the orchestrator. Needs a bounded
/// height (it lives in the wizard's expanded [AppDialog]).
class StartMembershipsStepBody extends StatelessWidget {
  final StartMembershipsStep step;
  final MemberDetailResponse launchMember;
  final MemberRepository repository;
  final StartMembershipParticipant payer;
  final MemberDetailResponse? payerDetail;
  final StartMembershipParticipant? currentMember;
  final Set<String> selectedMemberIds;
  final List<MembershipDraft> currentDrafts;

  /// Selected members in family order + every member's
  /// configured drafts — the review step's summary input.
  final List<StartMembershipParticipant> configMembers;
  final Map<String, List<MembershipDraft>> draftsByMember;
  final Map<String, String> disabledPlanReasons;

  /// The current member's existing non-terminal
  /// memberships — the Plans step's "Already has" block.
  final List<MembershipInfo> existingMemberships;
  final Future<List<MembershipPlanResponse>> plansFuture;
  final Future<List<DiscountResponse>> discountsFuture;
  final MemberMembershipsStartRequest? previewRequest;
  final MemberMembershipsStartPreview? preview;
  final ProrationBehavior prorationBehavior;
  final bool paidWithCash;
  final bool hasRecurring;
  final bool hasOneTime;
  final CustomCardCapture? customCard;
  final CardOnFile? payerCardOnFile;
  final Map<String, String> memberNames;
  final Map<String, String> planNames;

  final ValueChanged<StartMembershipParticipant>
      onPayerSelected;
  final ValueChanged<String> onMemberToggle;
  final VoidCallback onLinkFirst;
  final ValueChanged<MembershipPlanResponse> onPlanToggle;

  /// Applies [change] to the current member's draft for
  /// [planId] — the per-step dispatch (count stepper,
  /// preset toggles, customs) composes its transform here.
  final void Function(
    String planId,
    MembershipDraft Function(MembershipDraft) change,
  ) onDraftChanged;
  final ValueChanged<MemberMembershipsStartPreview>
      onPreviewLoaded;
  final ValueChanged<ProrationBehavior> onProrationChanged;
  final ValueChanged<bool> onPaidWithCashChanged;
  final VoidCallback onAddNewCard;
  final VoidCallback onAddOrChangeCustomCard;
  final VoidCallback onRemoveCustomCard;

  /// Review-step actions: edit jumps the wizard back into
  /// [memberId]'s plans/discounts; remove drops one draft.
  final ValueChanged<String> onEditMember;
  final void Function(String memberId, String planId)
      onRemoveDraft;
  final VoidCallback onRetryFailed;
  final VoidCallback onBackToPayment;
  final ValueChanged<String> onViewMember;

  const StartMembershipsStepBody({
    super.key,
    required this.step,
    required this.launchMember,
    required this.repository,
    required this.payer,
    required this.payerDetail,
    required this.currentMember,
    required this.selectedMemberIds,
    required this.currentDrafts,
    required this.configMembers,
    required this.draftsByMember,
    required this.disabledPlanReasons,
    required this.existingMemberships,
    required this.plansFuture,
    required this.discountsFuture,
    required this.previewRequest,
    required this.preview,
    required this.prorationBehavior,
    required this.paidWithCash,
    required this.hasRecurring,
    required this.hasOneTime,
    required this.customCard,
    required this.payerCardOnFile,
    required this.memberNames,
    required this.planNames,
    required this.onPayerSelected,
    required this.onMemberToggle,
    required this.onLinkFirst,
    required this.onPlanToggle,
    required this.onDraftChanged,
    required this.onPreviewLoaded,
    required this.onProrationChanged,
    required this.onPaidWithCashChanged,
    required this.onAddNewCard,
    required this.onAddOrChangeCustomCard,
    required this.onRemoveCustomCard,
    required this.onEditMember,
    required this.onRemoveDraft,
    required this.onRetryFailed,
    required this.onBackToPayment,
    required this.onViewMember,
  });

  bool get _isPerMemberStep =>
      step == StartMembershipsStep.plans ||
      step == StartMembershipsStep.discounts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      // Chrome zones (stepper, context header) and the
      // content area read as distinct surfaces.
      spacing: DesignConstants.spacingBig,
      children: [
        StartMembershipsStepIndicator(step: step),
        if (step != StartMembershipsStep.payer)
          StartMembershipsHeader(
            payer: payer,
            currentMember:
                _isPerMemberStep ? currentMember : null,
          ),
        Expanded(
          child: SingleChildScrollView(
            child: Center(
              // Tight width (clamped by the viewport) so
              // every step fills the same readable
              // measure, whitespace on both sides.
              child: SizedBox(
                width:
                    DesignConstants.dialogContentMaxWidth,
                child: _activeStep(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _activeStep() {
    switch (step) {
      case StartMembershipsStep.payer:
        return StartPayerStep(
          member: launchMember,
          payerMemberId: payer.memberId,
          payerName: payer.name,
          selectedMemberId: payer.memberId,
          onSelected: onPayerSelected,
        );
      case StartMembershipsStep.members:
        return StartMembersStep(
          payerDetail: payerDetail,
          payer: payer,
          selectedMemberIds: selectedMemberIds,
          onToggle: onMemberToggle,
          onLinkFirst: onLinkFirst,
        );
      case StartMembershipsStep.plans:
        return StartPlansStep(
          member: currentMember ?? payer,
          plansFuture: plansFuture,
          drafts: currentDrafts,
          disabledPlanReasons: disabledPlanReasons,
          existingMemberships: existingMemberships,
          onToggle: onPlanToggle,
          onCountChanged: (planId, count) =>
              onDraftChanged(
            planId,
            (d) => d.copyWith(count: count),
          ),
        );
      case StartMembershipsStep.discounts:
        return StartDiscountsStep(
          member: currentMember ?? payer,
          drafts: currentDrafts,
          discountsFuture: discountsFuture,
          onPresetToggle: (planId, discountId) =>
              onDraftChanged(
            planId,
            (d) => d.withPresetToggled(discountId),
          ),
          onCustomAdded: (planId, value) =>
              onDraftChanged(
            planId,
            (d) => d.withCustomAdded(value),
          ),
          onCustomRemoved: (planId, index) =>
              onDraftChanged(
            planId,
            (d) => d.withCustomRemovedAt(index),
          ),
        );
      case StartMembershipsStep.review:
        return StartReviewStep(
          members: configMembers,
          draftsByMember: draftsByMember,
          discountsFuture: discountsFuture,
          onEditMember: onEditMember,
          onRemoveDraft: onRemoveDraft,
        );
      case StartMembershipsStep.preview:
        final req = previewRequest;
        if (req == null) {
          return Text(
            'Nothing selected yet — go back and pick '
            'at least one membership.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          );
        }
        return StartPreviewStep(
          repository: repository,
          request: req,
          // The payer's current monthly bill is the "before"
          // baseline for the recurring card's before→after.
          currentMonthly: payerDetail?.totalMonthlyRecurringPrice,
          onLoaded: onPreviewLoaded,
          prorationBehavior: prorationBehavior,
          onProrationChanged: onProrationChanged,
          hasRecurring: hasRecurring,
          anchorDate: preview?.recurring?.nextPaymentAt,
        );
      case StartMembershipsStep.payment:
        return StartPaymentStep(
          cardOnFile: payerCardOnFile,
          paidWithCash: paidWithCash,
          onPaidWithCashChanged: onPaidWithCashChanged,
          hasRecurring: hasRecurring,
          hasOneTime: hasOneTime,
          customCard: customCard,
          onAddOrChangeCustomCard:
              onAddOrChangeCustomCard,
          onRemoveCustomCard: onRemoveCustomCard,
          preview: preview,
          prorationBehavior: prorationBehavior,
          onAddNewCard: onAddNewCard,
        );
      case StartMembershipsStep.results:
        return StartResultsStep(
          memberNames: memberNames,
          planNames: planNames,
          onRetryFailed: onRetryFailed,
          onBackToPayment: onBackToPayment,
          onViewMember: onViewMember,
        );
    }
  }
}
