import 'dart:developer';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_base.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_load.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_request.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_waiver_ops.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_card_capture.dart';

/// The review step's money, and the payment step's settlement choice.
///
/// The review and the old preview step are ONE screen here: the proration
/// choice is chosen where it visibly moves the total, instead of on a screen
/// that promised prices "on the next step" above a price on every row.
mixin MembershipWizardMoneyOps
    on MembershipWizardBase, MembershipWizardWaiverOps {
  /// Enter the review and stage its charge preview.
  ///
  /// The preview is ALWAYS fetched at `prorate_to_anchor`, whatever is chosen,
  /// so the response carries the full split (one-time + due-now + recurring).
  /// `no_charge` is exactly that split minus due-now, which is what lets the
  /// toggle re-derive locally instead of re-fetching — see [setProration].
  @override
  Future<void> enterReviewCharges() async {
    final request = buildWizardRequest(
      payerMemberId: state.payer.memberId,
      gymId: state.gymId,
      idempotencyKey: newIdempotencyKey(),
      prorationBehavior: ProrationBehavior.prorateToAnchor,
      paidWithCash: state.paidWithCash,
      memberships: state.pendingItems,
      customCard: state.customCard,
      oneOffCardBlock: state.oneOffCardBlock,
    );
    emit(
      state.copyWith(
        step: MembershipWizardStep.reviewCharges,
        editReturnsToReview: false,
        previewRequest: request,
        preview: null,
        previewLoad: request == null
            ? const MembershipWizardLoad.failed(
                'There is nothing to charge for yet.',
              )
            : const MembershipWizardLoad.loading(),
      ),
    );
    if (request == null) return;
    try {
      final preview = await memberRepo.previewStartMemberships(request);
      if (isClosed || !_isLivePreview(request)) return;
      emit(
        state.copyWith(
          preview: preview,
          previewLoad: const MembershipWizardLoad.ready(),
        ),
      );
    } on WaiverGateException catch (e, st) {
      // The preview is the first forward call to hit the gate, so this is the
      // BACKSTOP catching what the proactive queue missed — a plan whose
      // waiver list drifted, or a floor that moved mid-run.
      log('Membership wizard: preview waiver gate', error: e, stackTrace: st);
      if (isClosed || !_isLivePreview(request)) return;
      applyServerWaiverGate(e);
    } catch (e, st) {
      log('Membership wizard: charge preview failed',
          error: e, stackTrace: st);
      if (isClosed || !_isLivePreview(request)) return;
      emit(
        state.copyWith(
          previewLoad: const MembershipWizardLoad.failed(
            'Could not load the charge preview.',
          ),
        ),
      );
    }
  }

  /// Whether [request] is still the preview this run is waiting on.
  ///
  /// Two trash taps inside one round-trip fire two previews, and nothing makes
  /// the network answer in the order it was asked — so the FIRST cart's total
  /// can arrive last and land on the second cart, `ready`, with PAY enabled
  /// over a figure nothing will charge. `previewRequest` is the staged
  /// request's identity and EVERY cart or roster edit nulls it, so a response
  /// whose own request is no longer staged is dropped rather than rendered
  /// beside a cart it did not price. Quoting one number and charging another is
  /// the exact failure this step exists to prevent.
  ///
  /// It guards the failure and the 422 alike: a stale error would blank a live
  /// quote, and a stale gate would demand a signature for a cart that is gone.
  bool _isLivePreview(MemberMembershipsStartRequest request) =>
      identical(state.previewRequest, request);

  /// Re-run the preview after a failure.
  Future<void> retryPreview() => enterReviewCharges();

  /// Choose how the first recurring period is handled.
  ///
  /// A PURE local re-derive: the preview was fetched once with the full split,
  /// so switching to `no_charge` suppresses the due-now half and leaves the
  /// one-time and recurring figures identical. No request is rebuilt and
  /// nothing is re-fetched, so the breakdown never blanks — and PAY still
  /// submits the chosen behaviour.
  void setProration(ProrationBehavior behavior) {
    if (behavior == state.prorationBehavior) return;
    emit(state.copyWith(prorationBehavior: behavior));
  }

  /// Take the money as cash instead of a card.
  ///
  /// The one-off card is KEPT rather than dropped: turning cash back off
  /// restores it, so a mis-tap does not cost staff a re-typed card. It simply
  /// stops paying while cash is on, which [MembershipWizardState] exposes as a
  /// blocker with a reason rather than silently ignoring the card the way the
  /// old wizard did.
  void setPaidWithCash(bool paidWithCash) {
    if (paidWithCash == state.paidWithCash) return;
    emit(state.copyWith(paidWithCash: paidWithCash));
  }

  /// Hold a card entered at checkout for today's one-time invoice.
  void setCustomCard(CustomCardCapture card) {
    emit(state.copyWith(customCard: card));
  }

  /// Drop the one-off card.
  void clearCustomCard() {
    if (state.customCard == null) return;
    emit(state.copyWith(customCard: null));
  }

  /// Enter the payment step and mint THIS attempt's idempotency key.
  ///
  /// One key per arrival, so a double-tap on PAY posts one key rather than
  /// two; a retry after a landed start mints a fresh one.
  @override
  void enterPayment() {
    emit(
      state.copyWith(
        step: MembershipWizardStep.payment,
        idempotencyKey: newIdempotencyKey(),
        commitError: null,
      ),
    );
  }
}
