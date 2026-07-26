import 'package:flutter/material.dart';

import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_summary.dart';
import 'package:crm/features/member_details/presentation/dialogs/member_detail_bloc_settle.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/authorize_direction.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/change_payer_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/one_time_card_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_link_member_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_new_member_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/update_card_dialog.dart';

/// The staff dialogs that open OVER the run, and the sequencing each needs.
///
/// They are staff tooling over the flow rather than steps of it — a member
/// facing a lobby iPad can open none of them — so they stay dialogs and stay
/// here, off the cubit: every one needs a `Navigator`, and a run that reached
/// for one from its state layer would be a run a widget test could not pump.
///
/// The sequencing is the load-bearing part. An authorization is committed by
/// `MemberDetailBloc`, so the wizard must WAIT for that mutation to settle
/// ([awaitMemberDetailSettle]) before re-reading the payer — otherwise the
/// roster is rebuilt from a record that does not yet carry the person who was
/// just linked, and they silently fail to appear.
class WizardDialogRoutes {
  final MembershipWizardCubit cubit;
  final MemberDetailBloc detailBloc;

  /// The member whose page opened the run — the anchor every payer-side
  /// authorization is written against, whoever is paying by then.
  final MemberDetailResponse launchMember;

  const WizardDialogRoutes({
    required this.cubit,
    required this.detailBloc,
    required this.launchMember,
  });

  /// Create somebody new and authorize the PAYER for them, then tick them in.
  Future<void> addNewMember(BuildContext context) async {
    final payer = cubit.state.payer;
    final token = _refreshToken();
    final result = await StartNewMemberDialog.show(
      context: context,
      direction: AuthorizeDirection.addPayee,
      anchorMemberId: payer.memberId,
      anchorName: payer.name,
      gymId: cubit.state.gymId,
      relatedIds: _payeeIds(),
    );
    if (result == null) return;
    if (!result.committedLink) {
      // Already authorized — they simply join the run.
      cubit.setTraining(result.memberId, true);
      return;
    }
    await awaitMemberDetailSettle(detailBloc, token);
    await cubit.loadPayerDetail(alsoTrain: result.memberId);
  }

  /// Find an existing member and authorize the PAYER for them.
  Future<void> linkMember(BuildContext context) async {
    final payer = cubit.state.payer;
    final exclude = _payeeIds();
    final token = _refreshToken();
    final linkedId = await StartLinkMemberDialog.show(
      context: context,
      direction: AuthorizeDirection.addPayee,
      anchorMemberId: payer.memberId,
      anchorName: payer.name,
      candidates: _roster(exclude),
    );
    if (linkedId == null) return;
    await awaitMemberDetailSettle(detailBloc, token);
    await cubit.loadPayerDetail(alsoTrain: linkedId);
  }

  /// Change who pays — including creating or linking a NEW payer, which is
  /// the same two adders pointed the other way.
  Future<void> changePayer(BuildContext context) async {
    final chosen = await ChangePayerDialog.show(
      context: context,
      launchMember: launchMember,
      currentPayerId: cubit.state.payer.memberId,
      candidates: cubit.state.payerCandidates,
      onCreatePayer: () => _authorizeNewPayer(context),
      onLinkPayer: () => _authorizeLinkedPayer(context),
    );
    if (chosen == null) return;
    cubit.selectPayer(chosen);
  }

  /// Add or replace the PAYER's saved default card.
  ///
  /// Targeted at the payer explicitly rather than the viewed member: the run
  /// can be opened from a child's page, and the card a recurring membership
  /// bills is always the payer's.
  Future<void> updateSavedCard(BuildContext context) async {
    final token = _refreshToken();
    await UpdateCardDialog.show(
      context: context,
      memberName: cubit.state.payer.name,
      card: cubit.state.savedCard,
      targetMemberId: cubit.state.payer.memberId,
      // Removing a card mid-checkout makes no sense; removal lives on the
      // member profile behind its own confirmation.
      allowRemove: false,
    );
    await awaitMemberDetailSettle(detailBloc, token);
    await cubit.loadPayerDetail();
  }

  /// Capture a one-off card for a purely one-time cart.
  Future<void> captureOneOffCard(BuildContext context) async {
    final captured = await OneTimeCardDialog.show(context: context);
    if (captured == null) return;
    cubit.setCustomCard(captured);
  }

  /// Create a new member and authorize THEM as a payer for the launch member.
  Future<String?> _authorizeNewPayer(BuildContext context) async {
    final token = _refreshToken();
    final result = await StartNewMemberDialog.show(
      context: context,
      direction: AuthorizeDirection.addPayer,
      anchorMemberId: launchMember.memberId,
      anchorName: launchMember.fullName,
      gymId: cubit.state.gymId,
      relatedIds: _payerIds(),
    );
    if (result == null) return null;
    if (result.committedLink) {
      await awaitMemberDetailSettle(detailBloc, token);
      _refreshPayerCandidates();
    }
    return result.memberId;
  }

  /// Pick an existing member and authorize THEM as a payer.
  Future<String?> _authorizeLinkedPayer(BuildContext context) async {
    final exclude = _payerIds();
    final token = _refreshToken();
    final linkedId = await StartLinkMemberDialog.show(
      context: context,
      direction: AuthorizeDirection.addPayer,
      anchorMemberId: launchMember.memberId,
      anchorName: launchMember.fullName,
      candidates: _roster(exclude),
    );
    if (linkedId == null) return null;
    await awaitMemberDetailSettle(detailBloc, token);
    _refreshPayerCandidates();
    return linkedId;
  }

  /// The payer candidates, re-read off the reloaded LAUNCH member — whose
  /// `authorizedPayers` now carries whoever was just authorized.
  void _refreshPayerCandidates() {
    final state = detailBloc.state;
    if (state is! MemberDetailLoaded) return;
    cubit.setPayerCandidates(state.member.authorizedPayers);
  }

  int _refreshToken() {
    final state = detailBloc.state;
    return state is MemberDetailLoaded ? state.refreshToken : -1;
  }

  List<MemberSummary> _roster(Set<String> exclude) {
    final state = detailBloc.state;
    if (state is! MemberDetailLoaded) return const [];
    return [
      for (final member in state.allMembers)
        if (!exclude.contains(member.memberId)) member,
    ];
  }

  /// Everybody already on the payer's payee side — the adder never offers a
  /// person the payer can already pay for.
  Set<String> _payeeIds() => {
        for (final person in cubit.state.people) person.memberId,
      };

  /// Everybody already on the launch member's payer side.
  Set<String> _payerIds() => {
        launchMember.memberId,
        for (final account in cubit.state.payerCandidates) account.memberId,
      };
}
