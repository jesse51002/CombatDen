import 'dart:developer';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_base.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_outcome.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_request.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_results.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_waiver_ops.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_response.dart';

/// The money moment — the ONE call that charges a real card, and the four
/// defences around it.
///
/// The old wizard had none of them: PAY minted a key and posted, a second tap
/// posted again, and "retry the failed memberships" re-staged items with no
/// notion of what had actually been created. All four below are reimplemented
/// from the kiosk's signup cubit, which is the proven implementation — they
/// are deliberately NOT imported from it, because the two surfaces settle at
/// different moments and sharing the orchestration would couple the desk's
/// step machine to a lobby iPad's.
mixin MembershipWizardCommitOps
    on MembershipWizardBase, MembershipWizardWaiverOps {
  /// Every idempotency key a start POST has already gone out for.
  ///
  /// Once a request has left the device its outcome may be unknown, and
  /// re-posting the same key is the ONE action that could take a payer's money
  /// twice. A re-press on a key that already went out therefore HARD-STOPS
  /// with [MembershipWizardCommitError.unconfirmed] instead of re-posting; the
  /// desk confirms in Stripe.
  final Set<String> _sentAttempts = <String>{};

  /// Fire the start call.
  ///
  /// The `starting` check is SYNCHRONOUS and its emit happens before any
  /// `await`, so a double-tap on PAY is exactly one charge.
  Future<void> pay() async {
    if (state.starting) return;
    final key = state.idempotencyKey ?? newIdempotencyKey();
    if (_sentAttempts.contains(key)) {
      _stop(MembershipWizardCommitError.unconfirmed);
      return;
    }
    final request = _buildPayRequest(key);
    if (request == null) {
      log('Membership wizard: start request could not be assembled');
      _stop(MembershipWizardCommitError.nothingToSend);
      return;
    }
    await _send(request);
  }

  /// Retry exactly the memberships the landed start did NOT create, under a
  /// FRESH idempotency key.
  ///
  /// Both halves are load-bearing. The narrowing comes from
  /// [MembershipWizardState.retryScope], whose null-vs-empty distinction is
  /// the defence: null is "nothing landed, send the cart", empty is "nothing
  /// left to send" — collapse them and a `[created, unknown]` partial re-posts
  /// the WHOLE cart under a key the backend's replay guard cannot dedupe. And
  /// the key must be new: re-using the sent one would only trip the latch
  /// above instead of making a genuine attempt.
  Future<void> retryUncreated() async {
    if (state.starting) return;
    if (!state.canRetry) return;
    final key = newIdempotencyKey();
    if (_sentAttempts.contains(key)) {
      _stop(MembershipWizardCommitError.unconfirmed);
      return;
    }
    final request = _buildPayRequest(key);
    if (request == null) {
      log('Membership wizard: retry had nothing left to send');
      _stop(MembershipWizardCommitError.nothingToSend);
      return;
    }
    await _send(request);
  }

  /// Dismiss whatever the last attempt could not do, so the surface can offer
  /// the step again.
  void clearCommitError() {
    if (state.commitError == null) return;
    emit(state.copyWith(commitError: null));
  }

  /// This attempt's request: the pending items (the whole cart, or exactly the
  /// un-created ones), the CHOSEN proration, and the one-off card only where
  /// no blocker applies.
  MemberMembershipsStartRequest? _buildPayRequest(String key) =>
      buildWizardRequest(
        payerMemberId: state.payer.memberId,
        gymId: state.gymId,
        idempotencyKey: key,
        prorationBehavior: state.prorationBehavior,
        paidWithCash: state.paidWithCash,
        memberships: state.pendingItems,
        customCard: state.customCard,
        oneOffCardBlock: state.oneOffCardBlock,
        forPay: true,
      );

  /// Post the attempt and split its answer three ways.
  Future<void> _send(MemberMembershipsStartRequest request) async {
    final key = request.idempotencyKey;
    final previous = state.startResult;
    _sentAttempts.add(key);
    emit(
      state.copyWith(
        step: MembershipWizardStep.results,
        starting: true,
        idempotencyKey: key,
        // Cleared so the request already built above is the last thing the
        // retry scope narrowed; a landed answer replaces it below.
        startResult: null,
        commitError: null,
      ),
    );
    try {
      final landed = await memberRepo.startMemberships(request);
      if (isClosed) return;
      // A 207 is a 2xx: a decline arrives as a RESULT in the body, never as an
      // HTTP error, so the split is read off the ITEMS — all created, a
      // PARTIAL (money HAS moved for the group that cleared), or all failed.
      final merged = mergeStartResults(previous, landed);
      emit(
        state.copyWith(
          starting: false,
          startResult: merged,
          commitError: merged.results.isEmpty
              ? MembershipWizardCommitError.failed
              : null,
        ),
      );
    } on WaiverGateException catch (e, st) {
      log('Membership wizard: start waiver gate', error: e, stackTrace: st);
      if (isClosed) return;
      emit(state.copyWith(starting: false, startResult: previous));
      applyServerWaiverGate(e);
    } on ServerException catch (e, st) {
      if (isClosed) return;
      // 409 = an idempotent replay: the ORIGINAL start stands, charge
      // included, so nothing was taken twice and nothing may be re-sent.
      if (e.statusCode == 409) {
        _land(previous, MembershipWizardCommitError.alreadyStarted);
        return;
      }
      log('Membership wizard: start failed', error: e, stackTrace: st);
      _land(previous, MembershipWizardCommitError.failed);
    } catch (e, st) {
      log('Membership wizard: start failed', error: e, stackTrace: st);
      if (isClosed) return;
      _land(previous, MembershipWizardCommitError.failed);
    }
  }

  /// An attempt that produced no breakdown of its own — the earlier one's
  /// receipt is restored, because a failed retry must never erase what an
  /// earlier attempt created.
  void _land(
    MemberMembershipsStartResponse? previous,
    MembershipWizardCommitError error,
  ) {
    emit(
      state.copyWith(
        starting: false,
        startResult: previous,
        commitError: error,
      ),
    );
  }

  /// An attempt that never left the device. Nothing was sent, so nothing was
  /// charged — and the flow still lands somewhere that says so.
  void _stop(MembershipWizardCommitError error) {
    emit(
      state.copyWith(
        step: MembershipWizardStep.results,
        starting: false,
        commitError: error,
      ),
    );
  }
}
