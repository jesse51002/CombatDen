import 'dart:async';
import 'dart:developer';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_base.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_consequence.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_load.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_person.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_reads.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_roster.dart';
import 'package:crm/features/member_details/data/models/linked_account.dart';

/// The `who` step's controls: who pays, and who is getting a membership.
///
/// Every one of them can destroy picked work, so every one of them leaves a
/// [MembershipWizardConsequence] behind and can be ASKED what it would cost
/// before it is used. The old wizard did all three silently, with no undo.
mixin MembershipWizardRosterOps on MembershipWizardBase {
  /// Read the payer's own billing detail — their card, and the people they may
  /// pay for.
  ///
  /// A failure is a real error state with a retry, NOT a swallowed exception:
  /// the old wizard caught this one and returned, leaving the roster on a
  /// spinner that could never resolve and a Next that could never enable.
  Future<void> loadPayerDetail({String? alsoTrain}) async {
    emit(state.copyWith(payerLoad: const MembershipWizardLoad.loading()));
    try {
      final detail = await memberRepo.getMemberDetail(state.payer.memberId);
      if (isClosed) return;
      emit(
        state.copyWith(
          payerDetail: detail,
          payerLoad: const MembershipWizardLoad.ready(),
          memberDetails: {...state.memberDetails, detail.memberId: detail},
          trainingMemberIds: alsoTrain == null
              ? state.trainingMemberIds
              : {...state.trainingMemberIds, alsoTrain},
        ),
      );
      await loadFamilyDetails();
    } catch (e, st) {
      log(
        'Membership wizard: payer billing detail read failed',
        error: e,
        stackTrace: st,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          payerLoad: const MembershipWizardLoad.failed(
            'Could not load who this payer covers.',
          ),
        ),
      );
    }
  }

  /// Re-run the payer read after a failure — the retry path that failure state
  /// exists to give.
  Future<void> retryPayerDetail() => loadPayerDetail();

  /// Fill in the roster's own membership history, all at once. Best effort:
  /// somebody whose read fails is simply ungated on the client.
  Future<void> loadFamilyDetails() async {
    final wanted = <String>{
      for (final person in state.people)
        if (!state.memberDetails.containsKey(person.memberId)) person.memberId,
    };
    if (wanted.isEmpty) return;
    final landed = await gatherMemberDetails(memberRepo, wanted);
    if (isClosed || landed.isEmpty) return;
    emit(state.copyWith(memberDetails: {...state.memberDetails, ...landed}));
  }

  /// What switching to [memberId] would cost, for the control to state BEFORE
  /// it is used.
  MembershipWizardConsequence? consequenceOfPayerSwitch(String memberId) {
    if (memberId == state.payer.memberId) return null;
    final candidate = _payerParticipant(memberId);
    if (candidate == null) return null;
    return payerSwitchConsequence(
      toMemberId: candidate.memberId,
      toMemberName: candidate.name,
      launchMemberId: state.launchMemberId,
      people: state.people,
      drafts: state.drafts,
    );
  }

  /// What unticking [memberId] would cost.
  MembershipWizardConsequence? consequenceOfUntick(String memberId) {
    for (final person in state.people) {
      if (person.memberId != memberId) continue;
      return untickConsequence(person: person, drafts: state.drafts);
    }
    return null;
  }

  /// Change who pays.
  ///
  /// The roster is rebuilt rather than patched — who may be covered depends on
  /// who pays — so every pick in the run is dropped and the launch member (a
  /// valid participant for ANY chosen payer, since the choices are their own
  /// authorized payers) is the one who stays ticked. The consequence is
  /// recorded so the surface can say what went.
  void selectPayer(String memberId) {
    if (memberId == state.payer.memberId) return;
    final candidate = _payerParticipant(memberId);
    if (candidate == null) return;
    final consequence = consequenceOfPayerSwitch(memberId);
    final cached = state.memberDetails[memberId];
    emit(
      state.copyWith(
        payer: candidate,
        payerDetail: cached,
        payerLoad: cached == null
            ? const MembershipWizardLoad.loading()
            : const MembershipWizardLoad.ready(),
        trainingMemberIds: {state.launchMemberId},
        drafts: const {},
        personIndex: 0,
        preview: null,
        previewRequest: null,
        previewLoad: const MembershipWizardLoad.idle(),
        // Every pick is gone, so a refusal about them is too — see
        // `serverGate`. The switch would otherwise carry a demand to sign for
        // somebody this payer may not even cover.
        serverGate: const [],
        lastConsequence:
            consequence != null && consequence.destroys ? consequence : null,
      ),
    );
    // The ROSTER is what gates the plans, and it was just rebuilt from this
    // payer's own dependents — a different set of people from the last one,
    // whose history is a different set of reads. Skipping it because the
    // PAYER's own detail happened to be cached is how every plan card in a
    // switched-payer run ends up ungated, offering a recurring plan somebody
    // already holds and finding out at the money step.
    if (cached == null) {
      unawaited(loadPayerDetail());
    } else {
      unawaited(loadFamilyDetails());
    }
  }

  /// Turn "getting a membership" on or off for one person.
  ///
  /// Turning it OFF drops their lineup with it, so a stale pick cannot return
  /// the moment the row is re-ticked by accident — and the consequence records
  /// what went, so the drop is never invisible.
  void setTraining(String memberId, bool training) {
    if (training) {
      if (state.trainingMemberIds.contains(memberId)) return;
      emit(
        state.copyWith(
          trainingMemberIds: {...state.trainingMemberIds, memberId},
          preview: null,
          previewRequest: null,
          previewLoad: const MembershipWizardLoad.idle(),
          serverGate: const [],
          lastConsequence: null,
        ),
      );
      return;
    }
    if (!state.trainingMemberIds.contains(memberId)) return;
    final consequence = consequenceOfUntick(memberId);
    emit(
      state.copyWith(
        trainingMemberIds: {
          for (final id in state.trainingMemberIds)
            if (id != memberId) id,
        },
        drafts: draftsWithout(state.drafts, memberId),
        preview: null,
        previewRequest: null,
        previewLoad: const MembershipWizardLoad.idle(),
        // Their picks are gone, so a refusal naming them is too — see
        // `serverGate`. Otherwise the run keeps a waivers step for somebody the
        // request will not carry at all.
        serverGate: const [],
        lastConsequence:
            consequence != null && consequence.destroys ? consequence : null,
      ),
    );
    emit(state.copyWith(personIndex: clampPersonIndex(state.personIndex)));
  }

  /// The payer-side candidates, refreshed after a nested staff dialog
  /// authorized somebody new to pay for the launch member.
  void setPayerCandidates(List<LinkedAccount> candidates) {
    emit(state.copyWith(payerCandidates: candidates));
  }

  /// Dismiss the recorded consequence once the surface has stated it.
  void clearConsequence() {
    if (state.lastConsequence == null) return;
    emit(state.copyWith(lastConsequence: null));
  }

  /// The launch member (self-pay) or one of their authorized payers, as a
  /// roster row. Null for anybody who is neither.
  MembershipWizardPerson? _payerParticipant(String memberId) {
    if (memberId == state.launchMemberId) {
      final detail = state.memberDetails[state.launchMemberId];
      return MembershipWizardPerson(
        memberId: memberId,
        name: detail?.fullName ?? state.payer.name,
        email: detail?.personalInfo.email,
        photoUrl: detail?.photoUrl,
        isPayer: true,
      );
    }
    for (final account in state.payerCandidates) {
      if (account.memberId != memberId) continue;
      return MembershipWizardPerson(
        memberId: account.memberId,
        name: account.fullName,
        photoUrl: account.photoUrl,
        isPayer: true,
      );
    }
    return null;
  }
}
