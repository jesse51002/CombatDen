import 'dart:async';
import 'dart:developer';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_base.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_commit_ops.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_load.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_money_ops.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_person.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_plan_ops.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_roster_ops.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_waiver_ops.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/membership_flow/discounts/discounts_capability.dart';
import 'package:crm/features/membership_flow/domain/catalogue_policy.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';

/// The staff start-memberships flow: `who → plans (×N) → [waivers] →
/// reviewCharges → payment → results`.
///
/// It replaces a 950-line `StatefulWidget` that held every field locally, and
/// its two jobs are the step spine and the money path. Everything a RULE
/// decides — which plans a person may be sold, what a price string says, which
/// waivers are owed, what today's charge comes to, what the wire body looks
/// like — belongs to `features/membership_flow/` and is read from there, so a
/// change lands on this surface and the kiosk together or on neither.
///
/// Orchestration is deliberately NOT shared with the kiosk. The two settle at
/// different moments (the kiosk takes a card before its review, the desk
/// settles after it), and this is the layer holding the double-charge
/// defences, so one step machine serving both would couple a lobby iPad's
/// escape rules to a dialog's footer. The defences themselves are
/// reimplemented from the kiosk's proven cubit rather than imported.
class MembershipWizardCubit extends MembershipWizardBase
    with
        MembershipWizardRosterOps,
        MembershipWizardPlanOps,
        MembershipWizardWaiverOps,
        MembershipWizardMoneyOps,
        MembershipWizardCommitOps {
  MembershipWizardCubit({
    required MemberRepository memberRepository,
    required MembershipsRepository membershipsRepository,
    required MemberDetailResponse launchMember,

    /// Who starts ticked. The add-member group flow passes the whole group so
    /// everybody the payer just authorized is pre-checked; a member-detail
    /// launch leaves it null and only the viewed member is ticked.
    Set<String>? initialTrainingMemberIds,
    super.uuid,
  }) : super(
          memberRepo: memberRepository,
          membershipsRepo: membershipsRepository,
          initial: MembershipWizardState(
            gymId: launchMember.gymId,
            launchMemberId: launchMember.memberId,
            payer: MembershipWizardPerson(
              memberId: launchMember.memberId,
              name: launchMember.fullName,
              email: launchMember.personalInfo.email,
              photoUrl: launchMember.photoUrl,
              isPayer: true,
            ),
            // The viewed member's page already carries their billing detail,
            // so the flow opens ANSWERED rather than on a spinner.
            payerDetail: launchMember,
            payerLoad: const MembershipWizardLoad.ready(),
            payerCandidates: launchMember.authorizedPayers,
            memberDetails: {launchMember.memberId: launchMember},
            trainingMemberIds:
                (initialTrainingMemberIds != null &&
                        initialTrainingMemberIds.isNotEmpty)
                    ? initialTrainingMemberIds
                    : {launchMember.memberId},
          ),
        );

  /// Read what the flow needs before staff can answer anything: the gym's
  /// catalogue, its discounts, and the roster's own membership history.
  ///
  /// All three run CONCURRENTLY. The old wizard walked the family one member
  /// at a time, so a four-person family was four round trips deep before the
  /// plans step could gate a single card.
  Future<void> open() async {
    await Future.wait([
      loadCatalogue(),
      loadDiscounts(),
      loadFamilyDetails(),
    ]);
  }

  /// The gym's SELLABLE plans — public, and priced. The filter is the shared
  /// catalogue policy, which the kiosk applies too: a plan the desk can sell
  /// is exactly the plan the iPad can.
  Future<void> loadCatalogue() async {
    emit(state.copyWith(plansLoad: const MembershipWizardLoad.loading()));
    try {
      final all = await memberRepo.listMembershipPlans(state.gymId);
      if (isClosed) return;
      emit(
        state.copyWith(
          plans: sellablePlans(all),
          plansLoad: const MembershipWizardLoad.ready(),
        ),
      );
    } catch (e, st) {
      log('Membership wizard: plan catalogue load failed',
          error: e, stackTrace: st);
      if (isClosed) return;
      emit(
        state.copyWith(
          plansLoad: const MembershipWizardLoad.failed(
            'Could not load this gym\'s plans.',
          ),
        ),
      );
    }
  }

  /// The gym's discount presets. A failure leaves the capability EMPTY rather
  /// than absent: a desk with no presets can still give one member a one-off,
  /// so the plans step keeps its custom form.
  Future<void> loadDiscounts() async {
    emit(state.copyWith(discountsLoad: const MembershipWizardLoad.loading()));
    try {
      final presets = await memberRepo.listGymDiscounts(state.gymId);
      if (isClosed) return;
      emit(
        state.copyWith(
          discounts: DiscountsCapability(presets: presets),
          discountsLoad: const MembershipWizardLoad.ready(),
        ),
      );
    } catch (e, st) {
      log('Membership wizard: discount catalogue load failed',
          error: e, stackTrace: st);
      if (isClosed) return;
      emit(
        state.copyWith(
          discountsLoad: const MembershipWizardLoad.failed(
            'Could not load this gym\'s discounts.',
          ),
        ),
      );
    }
  }

  /// Whether the step on screen may be left backwards.
  bool get canGoBack =>
      state.step != MembershipWizardStep.who &&
      state.step != MembershipWizardStep.results;

  /// The forward move. PAY is NOT one of them — the money has its own action.
  Future<void> next() async {
    if (!state.canAdvance) return;
    switch (state.step) {
      case MembershipWizardStep.who:
        goTo(MembershipWizardStep.plans, personIndex: 0);
        // Which waivers each person has already signed, read as the plans step
        // opens: the answer must be in hand before the first waiver is drawn,
        // or a late read would re-shape a queue somebody is looking at.
        unawaited(loadSatisfiedWaivers());
      case MembershipWizardStep.plans:
        await _leavePlans();
      case MembershipWizardStep.waivers:
        await enterReviewCharges();
      case MembershipWizardStep.reviewCharges:
        enterPayment();
      case MembershipWizardStep.payment:
      case MembershipWizardStep.results:
        break;
    }
  }

  /// The back move.
  Future<void> back() async {
    switch (state.step) {
      case MembershipWizardStep.who:
      case MembershipWizardStep.results:
        break;
      case MembershipWizardStep.plans:
        if (state.editReturnsToReview) {
          // Back mid-edit abandons the edit and returns to the review, which
          // re-prices whatever the edit left behind.
          emit(state.copyWith(editReturnsToReview: false));
          await enterReviewCharges();
          return;
        }
        if (state.personIndex == 0) {
          goTo(MembershipWizardStep.who);
          return;
        }
        goTo(MembershipWizardStep.plans, personIndex: state.personIndex - 1);
      case MembershipWizardStep.waivers:
        _toLastPlansStep();
      case MembershipWizardStep.reviewCharges:
        // The LAST training person's plans step, resolved from the roster as
        // it stands — never a remembered index, which is how the old wizard
        // landed staff on somebody who had left the run. It skips the waiver
        // step deliberately: a signature cannot be taken back, so a re-entered
        // waiver run with nothing left to sign would bounce straight forward.
        _toLastPlansStep();
      case MembershipWizardStep.payment:
        await enterReviewCharges();
    }
  }

  /// Leaving one person's plans step: back to the review when this was an
  /// edit, on to the next training person, or out of the loop entirely.
  Future<void> _leavePlans() async {
    if (state.editReturnsToReview) {
      emit(state.copyWith(editReturnsToReview: false));
      await enterReviewCharges();
      return;
    }
    if (state.personIndex + 1 < state.trainingPeople.length) {
      goTo(MembershipWizardStep.plans, personIndex: state.personIndex + 1);
      return;
    }
    if (state.hasWaivers) {
      goTo(MembershipWizardStep.waivers);
      await loadCurrentWaiver();
      return;
    }
    await enterReviewCharges();
  }

  void _toLastPlansStep() {
    goTo(
      MembershipWizardStep.plans,
      personIndex: state.trainingPeople.length - 1,
    );
  }
}
