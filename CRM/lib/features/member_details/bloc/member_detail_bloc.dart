import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/check_in/data/models/check_in_request.dart';
import 'package:crm/features/check_in/data/models/check_in_response.dart';
import 'package:crm/features/check_in/data/models/signup_response.dart';
import 'package:crm/features/member_details/bloc/invoice_poller.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/cancel_outcome.dart';
import 'package:crm/features/member_details/data/models/member_memberships_freeze_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_mark_paid_cash_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_unfreeze_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_add_discounts_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_remove_discounts_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_update_price_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_upgrade_request.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/features/rewards/data/repositories/rewards_repository.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';

/// BLoC for the Specific Member Detail screen.
class MemberDetailBloc
    extends Bloc<MemberDetailEvent, MemberDetailState> {
  final MemberRepository _repository;
  final RanksRepository _ranksRepository;

  /// Reserve (sign-up) is a cross-feature reuse of the schedule feature's
  /// wiring (`ScheduleRepository.signUp`) for this one member/occurrence —
  /// there is no `MemberRepository` equivalent.
  final ScheduleRepository _scheduleRepository;

  /// Approve/reject of a pending redemption reuse the rewards feature's
  /// repository (`RewardsRepository.approve/reject`) — the same endpoints
  /// the Loyalty tab drives, so there is a single redemption client.
  final RewardsRepository _rewardsRepository;

  /// Drives the post-charge invoice poll (5/10/15/30/60s). Each
  /// charge / start / refund / mark-paid-cash restarts it, so a new
  /// charge mid-window resets the schedule — only one sequence runs.
  final InvoicePoller _poller;

  /// Monotonic per-tick sequence. Bloc processes events concurrently,
  /// so two ticks whose re-fetches overlap could otherwise let the
  /// slower (older) response overwrite the newer one. Each tick claims
  /// the next number and only emits if still the latest — newest-wins,
  /// so a stale re-fetch can never clobber a fresher one.
  int _pollSeq = 0;

  MemberDetailBloc({
    required MemberRepository repository,
    required ScheduleRepository scheduleRepository,
    required RanksRepository ranksRepository,
    required RewardsRepository rewardsRepository,
    InvoicePoller? poller,
  })  : _repository = repository,
        _scheduleRepository = scheduleRepository,
        _ranksRepository = ranksRepository,
        _rewardsRepository = rewardsRepository,
        _poller = poller ?? InvoicePoller(),
        super(const MemberDetailInitial()) {
    on<MemberDetailRequested>(_onDetailRequested);
    on<MemberSearchChanged>(_onSearchChanged);
    on<MembershipPageChanged>(_onPageChanged);
    on<MemberActionErrorCleared>(_onActionErrorCleared);

    on<EditMemberRequested>(_onEditMember);
    on<MemberRankChangeRequested>(_onRankChange);
    on<UpdateCardRequested>(_onUpdateCard);
    on<UnlinkPaymentRequested>(_onUnlinkPayment);
    on<LinkParentRequested>(_onLinkParent);
    on<RemoveAuthorizationRequested>(_onRemoveAuthorization);
    on<RemoveAuthorizationOutcomeCleared>(
      _onRemoveAuthorizationOutcomeCleared,
    );

    on<StartMembershipsRequested>(_onStartMemberships);
    on<StartMembershipsCleared>(
      _onStartMembershipsCleared,
    );
    on<CancelMembershipRequested>(_onCancelMembership);
    on<CancelMembershipOutcomeCleared>(
      _onCancelMembershipOutcomeCleared,
    );
    on<UpdatePriceRequested>(_onUpdatePrice);
    on<UpgradeMembershipRequested>(_onUpgradeMembership);
    on<UpgradeMembershipOutcomeCleared>(
      _onUpgradeMembershipOutcomeCleared,
    );
    on<CancelOneTimeMembershipRequested>(_onCancelOneTimeMembership);
    on<CancelOneTimeOutcomeCleared>(_onCancelOneTimeOutcomeCleared);
    on<FreezeAccountRequested>(_onFreezeAccount);
    on<UnfreezeAccountRequested>(_onUnfreezeAccount);
    on<MarkPaidCashRequested>(_onMarkPaidCash);

    on<AddDiscountsRequested>(_onAddDiscounts);
    on<RemoveDiscountsRequested>(_onRemoveDiscounts);

    on<ChargeCardRequested>(_onChargeCard);
    on<ChargeCardOutcomeCleared>(_onChargeCardOutcomeCleared);
    on<RefundChargeRequested>(_onRefundCharge);

    on<MemberCheckInRequested>(_onCheckIn);
    on<MemberCheckInCleared>(_onCheckInCleared);

    on<MemberReserveRequested>(_onReserve);
    on<MemberReserveCleared>(_onReserveCleared);

    on<ApproveRedemptionRequested>(_onApproveRedemption);
    on<RejectRedemptionRequested>(_onRejectRedemption);
    on<RedeemRewardForMemberRequested>(
      _onRedeemRewardForMember,
    );
    on<AdjustPointsRequested>(_onAdjustPoints);

    on<InvoicePollRequested>(_onInvoicePoll);
  }

  /// Backend `date` body fields are bare `YYYY-MM-DD` (gym-local, no tz).
  static final DateFormat _occurrenceDate = DateFormat('yyyy-MM-dd');

  // ----- Load + UI handlers -----

  Future<void> _onDetailRequested(
    MemberDetailRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    emit(const MemberDetailLoading());
    try {
      final results = await Future.wait([
        _repository.getMemberDetail(event.memberId),
        _repository.getAllMembers(event.gymId),
      ]);
      final member = results[0] as dynamic;
      final allMembers = results[1] as List<dynamic>;
      emit(MemberDetailLoaded(
        member: member,
        allMembers: allMembers.cast(),
        filteredMembers: allMembers.cast(),
      ));
    } catch (e, stackTrace) {
      log(
        'Failed to load member detail',
        error: e,
        stackTrace: stackTrace,
      );
      emit(MemberDetailError(
        e.toString(),
        memberId: event.memberId,
        statusCode: e is ServerException ? e.statusCode : null,
      ));
    }
  }

  void _onSearchChanged(
    MemberSearchChanged event,
    Emitter<MemberDetailState> emit,
  ) {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    final query = event.query.toLowerCase().trim();
    if (query.isEmpty) {
      emit(s.copyWith(
        filteredMembers: s.allMembers,
        searchQuery: '',
      ));
      return;
    }
    final filtered = s.allMembers
        .where(
          (m) =>
              m.fullName.toLowerCase().contains(query),
        )
        .toList();
    emit(s.copyWith(
      filteredMembers: filtered,
      searchQuery: query,
    ));
  }

  void _onPageChanged(
    MembershipPageChanged event,
    Emitter<MemberDetailState> emit,
  ) {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    emit(s.copyWith(
      currentMembershipIndex: event.pageIndex,
    ));
  }

  void _onActionErrorCleared(
    MemberActionErrorCleared event,
    Emitter<MemberDetailState> emit,
  ) {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    emit(s.copyWith(clearActionError: true));
  }

  // ----- Mutation helper -----

  /// Standard mutation flow: mark `isMutating`, run
  /// [action], refresh member detail on success, surface
  /// the error message on failure.
  ///
  /// When [pollInvoices] is true (the refund / mark-paid-cash
  /// actions, which settle an invoice asynchronously via a Stripe
  /// webhook), the post-charge invoice poll starts on success so the
  /// settled invoice surfaces without a manual reload.
  Future<void> _runMutation({
    required String actionLabel,
    required Emitter<MemberDetailState> emit,
    required Future<void> Function() action,
    bool pollInvoices = false,
  }) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;

    emit(s.copyWith(
      isMutating: true,
      clearActionError: true,
    ));

    try {
      await action();
      final refreshed = await _repository.getMemberDetail(
        s.member.memberId,
      );
      // Re-read state post-await: a page/search change that arrived
      // during the awaits must survive the mutation refresh, not be
      // clobbered by the stale pre-await snapshot.
      final current = state;
      if (current is! MemberDetailLoaded) return;
      emit(current.copyWith(
        member: refreshed,
        isMutating: false,
        clearActionError: true,
        refreshToken: current.refreshToken + 1,
      ));
      if (pollInvoices) _startInvoicePolling();
    } catch (e, stackTrace) {
      log(
        '$actionLabel failed',
        error: e,
        stackTrace: stackTrace,
      );
      final current = state;
      if (current is! MemberDetailLoaded) return;
      emit(current.copyWith(
        isMutating: false,
        actionError: e.toString(),
      ));
    }
  }

  // ----- Member profile mutations -----

  Future<void> _onEditMember(
    EditMemberRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    await _runMutation(
      actionLabel: 'Edit member',
      emit: emit,
      action: () => _repository.updateMember(
        s.member.memberId,
        event.request,
      ),
    );
  }

  Future<void> _onUpdateCard(
    UpdateCardRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    await _runMutation(
      actionLabel: 'Update card',
      emit: emit,
      action: () => _repository.updateMemberCard(
        event.targetMemberId ?? s.member.memberId,
        event.paymentMethodId,
      ),
    );
  }

  Future<void> _onUnlinkPayment(
    UnlinkPaymentRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    await _runMutation(
      actionLabel: 'Unlink payment',
      emit: emit,
      action: () => _repository.unlinkMemberPayment(
        s.member.memberId,
      ),
    );
  }

  Future<void> _onLinkParent(
    LinkParentRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    await _runMutation(
      actionLabel: 'Authorize payer',
      emit: emit,
      action: () => _repository.linkMemberAccount(
        event.memberId,
        payerMemberId: event.payerMemberId,
        waiverVersionId: event.waiverVersionId,
        signerName: event.signerName,
        consentAcknowledged: event.consentAcknowledged,
      ),
    );
  }

  Future<void> _onRemoveAuthorization(
    RemoveAuthorizationRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    emit(s.copyWith(
      isRemovingAuthorization: true,
      clearRemoveAuthorizationOutcome: true,
      clearActionError: true,
    ));

    // Generate the idempotency key ONCE per user action, so a retried
    // remove-authorization dedups at Stripe (the backend derives the payer's
    // sub-key from it).
    CancelOutcome outcome;
    try {
      outcome = await _repository.removeAuthorization(
        event.memberId,
        event.payerMemberId,
        const Uuid().v4(),
      );
    } catch (e, stackTrace) {
      // A hard failure (not a structured partial) — the unlink could not be
      // completed. Surface it on the screen-level error path WITHOUT a
      // completion outcome, so the dialog doesn't show an empty "done" screen.
      log(
        'Remove authorization failed',
        error: e,
        stackTrace: stackTrace,
      );
      final current = state;
      if (current is! MemberDetailLoaded) return;
      emit(current.copyWith(
        isRemovingAuthorization: false,
        actionError: e.toString(),
      ));
      return;
    }

    // Refresh member detail so the rosters/carousel reflect the unlink (even on
    // a partial, the de-authorize may not have run). Best-effort: emit the
    // outcome even if the refresh fails.
    MemberDetailLoaded? refreshed;
    try {
      final detail = await _repository.getMemberDetail(
        s.member.memberId,
      );
      // Re-read state post-await (see [_runMutation]).
      final current = state;
      if (current is MemberDetailLoaded) {
        refreshed = current.copyWith(
          member: detail,
          isRemovingAuthorization: false,
          removeAuthorizationOutcome: outcome,
          refreshToken: current.refreshToken + 1,
        );
      }
    } catch (e, stackTrace) {
      log(
        'Remove authorization: member refresh failed (non-fatal)',
        error: e,
        stackTrace: stackTrace,
      );
    }

    final current = state;
    if (current is! MemberDetailLoaded) return;
    emit(
      refreshed ??
          current.copyWith(
            isRemovingAuthorization: false,
            removeAuthorizationOutcome: outcome,
          ),
    );
  }

  void _onRemoveAuthorizationOutcomeCleared(
    RemoveAuthorizationOutcomeCleared event,
    Emitter<MemberDetailState> emit,
  ) {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    emit(s.copyWith(clearRemoveAuthorizationOutcome: true));
  }

  // ----- Membership mutations -----

  /// The wizard's one mutation. Unlike [_runMutation] the
  /// outcome must reach the wizard's results step, so the
  /// breakdown (or the failure message) lands on the state
  /// as `startResult` / `startError` instead of
  /// `actionError` — the screen-level error dialog must not
  /// swallow it while the wizard is open. The member detail
  /// is refreshed even on a partial failure: some
  /// memberships may have been created.
  Future<void> _onStartMemberships(
    StartMembershipsRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    emit(s.copyWith(
      isStartingMemberships: true,
      clearStartOutcome: true,
    ));
    try {
      final result =
          await _repository.startMemberships(event.request);
      final refreshed = await _repository.getMemberDetail(
        s.member.memberId,
      );
      // Re-read state post-await (see [_runMutation]).
      final current = state;
      if (current is! MemberDetailLoaded) return;
      emit(current.copyWith(
        member: refreshed,
        isStartingMemberships: false,
        startResult: result,
        refreshToken: current.refreshToken + 1,
      ));
      // The POST didn't throw, so memberships (and their first
      // invoices) may have been created — poll even on a partial
      // failure, where some items succeeded.
      _startInvoicePolling();
    } catch (e, stackTrace) {
      log(
        'Start memberships failed',
        error: e,
        stackTrace: stackTrace,
      );
      final current = state;
      if (current is! MemberDetailLoaded) return;
      if (e is WaiverGateException) {
        // 422 waiver gate — route the wizard to the sign-waivers step
        // rather than showing a generic error.
        emit(current.copyWith(
          isStartingMemberships: false,
          waiverGate: e,
        ));
      } else {
        emit(current.copyWith(
          isStartingMemberships: false,
          startError: e is ServerException
              ? (e.detail ?? e.message)
              : e.toString(),
        ));
      }
    }
  }

  void _onStartMembershipsCleared(
    StartMembershipsCleared event,
    Emitter<MemberDetailState> emit,
  ) {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    emit(s.copyWith(clearStartOutcome: true));
  }

  /// The cancel dialog's mutation. Unlike [_runMutation] the
  /// outcome must reach the dialog's completion step, so it
  /// lands on `isCancellingMemberships` / `cancelOutcome`
  /// instead of `isMutating` / `actionError` — the
  /// screen-level error overlay must not fire while the dialog
  /// is open (mirrors [_onStartMemberships] / [_onChargeCard]).
  /// Member detail is always refreshed (even on failure) so the
  /// carousel reflects the true post-cancel state.
  Future<void> _onCancelMembership(
    CancelMembershipRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    emit(s.copyWith(
      isCancellingMemberships: true,
      clearCancelOutcome: true,
    ));
    CancelOutcome outcome;
    try {
      outcome = await _repository.cancelMemberships(
        itemIds: event.itemIds,
        memberId: event.memberId,
        idempotencyKey: const Uuid().v4(),
      );
    } catch (e, stackTrace) {
      // MembershipInTaskException or unexpected — surface as all-failed.
      log(
        'Cancel membership failed',
        error: e,
        stackTrace: stackTrace,
      );
      outcome = CancelOutcome(
        succeededItemIds: const [],
        failedItemIds: event.itemIds,
      );
    }

    // Refresh member detail so the carousel reflects the true state
    // (even on failure, a partial cancel may have landed). Best-effort:
    // emit the outcome even if the refresh fails.
    MemberDetailLoaded? refreshed;
    try {
      final detail = await _repository.getMemberDetail(
        s.member.memberId,
      );
      // Re-read state post-await (see [_runMutation]).
      final current = state;
      if (current is MemberDetailLoaded) {
        refreshed = current.copyWith(
          member: detail,
          isCancellingMemberships: false,
          cancelOutcome: outcome,
          refreshToken: current.refreshToken + 1,
        );
      }
    } catch (e, stackTrace) {
      log(
        'Cancel: member refresh failed (non-fatal)',
        error: e,
        stackTrace: stackTrace,
      );
    }

    final current = state;
    if (current is! MemberDetailLoaded) return;
    emit(
      refreshed ??
          current.copyWith(
            isCancellingMemberships: false,
            cancelOutcome: outcome,
          ),
    );
  }

  void _onCancelMembershipOutcomeCleared(
    CancelMembershipOutcomeCleared event,
    Emitter<MemberDetailState> emit,
  ) {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    emit(s.copyWith(clearCancelOutcome: true));
  }

  Future<void> _onUpdatePrice(
    UpdatePriceRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    await _runMutation(
      actionLabel: 'Update price',
      emit: emit,
      action: () => _repository.updateMembershipPrice(
        MemberMembershipsUpdatePriceRequest(
          itemId: event.itemId,
          memberId: event.memberId,
          prorationBehavior: event.prorationBehavior,
          idempotencyKey: const Uuid().v4(),
        ),
      ),
    );
  }

  /// Cross-plan upgrade. Like [_onChargeCard], it rides a dedicated
  /// channel ([isUpgrading] / [upgradeSuccess] / [upgradeError]) instead
  /// of [_runMutation] so the screen-level overlay + error dialog never
  /// fire while the upgrade dialog is open; the dialog flips to its own
  /// success step on the bumped token. Member detail is re-fetched on
  /// success so the carousel + Payment History refresh behind the
  /// still-open step.
  Future<void> _onUpgradeMembership(
    UpgradeMembershipRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    emit(s.copyWith(
      isUpgrading: true,
      clearUpgradeOutcome: true,
    ));
    try {
      await _repository.upgradeMembership(
        MemberMembershipsUpgradeRequest(
          itemId: event.itemId,
          memberId: event.memberId,
          targetPlanId: event.targetPlanId,
          prorationBehavior: event.prorationBehavior,
          idempotencyKey: const Uuid().v4(),
        ),
      );
    } catch (e, stackTrace) {
      log('Upgrade membership failed', error: e, stackTrace: stackTrace);
      final current = state;
      if (current is! MemberDetailLoaded) return;
      emit(current.copyWith(
        isUpgrading: false,
        upgradeError: e is ServerException
            ? (e.detail ?? e.message)
            : e.toString(),
      ));
      return;
    }

    // The upgrade committed — the prorated difference (if any) is charged.
    // Commit success now so a follow-up refresh failure can never make a
    // real upgrade look failed. Mirrors [_onChargeCard].
    final committed = state;
    if (committed is! MemberDetailLoaded) return;
    emit(committed.copyWith(
      isUpgrading: false,
      upgradeSuccess: committed.upgradeSuccess + 1,
      refreshToken: committed.refreshToken + 1,
    ));
    // The prorated-difference invoice lands asynchronously (Stripe
    // webhook), so poll to surface it without a reload.
    _startInvoicePolling();
    try {
      final refreshed = await _repository.getMemberDetail(s.member.memberId);
      final latest = state;
      if (latest is MemberDetailLoaded) {
        emit(latest.copyWith(member: refreshed));
      }
    } catch (e, stackTrace) {
      log(
        'Upgrade succeeded but member refresh failed (non-fatal)',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _onUpgradeMembershipOutcomeCleared(
    UpgradeMembershipOutcomeCleared event,
    Emitter<MemberDetailState> emit,
  ) {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    emit(s.copyWith(clearUpgradeOutcome: true));
  }

  /// End a one-time / trial membership. Like [_onUpgradeMembership], it
  /// rides a dedicated channel ([isEnding] / [endSuccess] / [endError]) so
  /// the end dialog owns its own processing → success step (the screen-level
  /// overlay + error dialog never fire while it is open). No Stripe / no
  /// invoice, so — unlike upgrade — it does NOT poll for an invoice.
  Future<void> _onCancelOneTimeMembership(
    CancelOneTimeMembershipRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    emit(s.copyWith(
      isEnding: true,
      clearEndOutcome: true,
    ));
    try {
      await _repository.cancelOneTimeMembership(
        itemId: event.itemId,
        memberId: event.memberId,
      );
    } catch (e, stackTrace) {
      log('Cancel one-time membership failed', error: e, stackTrace: stackTrace);
      final current = state;
      if (current is! MemberDetailLoaded) return;
      emit(current.copyWith(
        isEnding: false,
        endError: e is ServerException
            ? (e.detail ?? e.message)
            : e.toString(),
      ));
      return;
    }

    // The end committed. Commit success now so a follow-up refresh failure
    // can't make a real end look failed. Mirrors [_onUpgradeMembership].
    final committed = state;
    if (committed is! MemberDetailLoaded) return;
    emit(committed.copyWith(
      isEnding: false,
      endSuccess: committed.endSuccess + 1,
      refreshToken: committed.refreshToken + 1,
    ));
    try {
      final refreshed = await _repository.getMemberDetail(s.member.memberId);
      final latest = state;
      if (latest is MemberDetailLoaded) {
        emit(latest.copyWith(member: refreshed));
      }
    } catch (e, stackTrace) {
      log(
        'End succeeded but member refresh failed (non-fatal)',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _onCancelOneTimeOutcomeCleared(
    CancelOneTimeOutcomeCleared event,
    Emitter<MemberDetailState> emit,
  ) {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    emit(s.copyWith(clearEndOutcome: true));
  }

  Future<void> _onFreezeAccount(
    FreezeAccountRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    await _runMutation(
      actionLabel: 'Freeze member',
      emit: emit,
      action: () => _repository.freezeAccount(
        MemberMembershipsFreezeRequest(
          memberId: s.member.memberId,
          gymId: s.member.gymId,
          freezeMonths: event.freezeMonths,
          idempotencyKey: const Uuid().v4(),
        ),
      ),
    );
  }

  Future<void> _onUnfreezeAccount(
    UnfreezeAccountRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    await _runMutation(
      actionLabel: 'Unfreeze member',
      emit: emit,
      action: () => _repository.unfreezeAccount(
        MemberMembershipsUnfreezeRequest(
          memberId: s.member.memberId,
          gymId: s.member.gymId,
          idempotencyKey: const Uuid().v4(),
        ),
      ),
    );
  }

  Future<void> _onMarkPaidCash(
    MarkPaidCashRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    await _runMutation(
      actionLabel: 'Mark paid cash',
      emit: emit,
      pollInvoices: true,
      action: () => _repository.markMembershipPaidCash(
        MemberMembershipsMarkPaidCashRequest(
          itemId: event.itemId,
          memberId: event.memberId,
          idempotencyKey: const Uuid().v4(),
        ),
      ),
    );
  }

  Future<void> _onAddDiscounts(
    AddDiscountsRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    await _runMutation(
      actionLabel: 'Add discounts',
      emit: emit,
      action: () async {
        await _repository.addMembershipDiscounts(
          MemberMembershipsAddDiscountsRequest(
            itemId: event.itemId,
            memberId: event.memberId,
            discountIds: event.discountIds,
            idempotencyKey: const Uuid().v4(),
          ),
        );
      },
    );
  }

  Future<void> _onRemoveDiscounts(
    RemoveDiscountsRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    await _runMutation(
      actionLabel: 'Remove discounts',
      emit: emit,
      action: () async {
        await _repository.removeMembershipDiscounts(
          MemberMembershipsRemoveDiscountsRequest(
            itemId: event.itemId,
            memberId: event.memberId,
            appliedIds: event.appliedIds,
            idempotencyKey: const Uuid().v4(),
          ),
        );
      },
    );
  }

  // ----- Charges / refunds -----

  /// The charge dialog's mutation. Unlike [_runMutation] the
  /// outcome must reach the dialog's in-dialog success / error
  /// steps, so it lands on `isChargingCard` /
  /// `chargeCardSuccess` / `chargeCardError` instead of
  /// `isMutating` / `actionError` — the screen-level overlay
  /// and error dialog must not fire while the dialog is open
  /// (mirrors [_onStartMemberships]). Member detail is
  /// re-fetched on success so Payment History refreshes behind
  /// the still-open success step.
  Future<void> _onChargeCard(
    ChargeCardRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    emit(s.copyWith(
      isChargingCard: true,
      clearChargeOutcome: true,
    ));
    try {
      await _repository.chargeCard(
        memberId: s.member.memberId,
        paidByMemberId: event.paidByMemberId,
        gymId: s.member.gymId,
        amount: event.amount,
        reason: event.description,
        paymentMethodId: event.paymentMethodId,
        paidCash: event.paidCash,
        idempotencyKey: const Uuid().v4(),
      );
    } catch (e, stackTrace) {
      log('Charge card failed', error: e, stackTrace: stackTrace);
      final current = state;
      if (current is! MemberDetailLoaded) return;
      emit(current.copyWith(
        isChargingCard: false,
        chargeCardError: e is ServerException
            ? (e.detail ?? e.message)
            : e.toString(),
      ));
      return;
    }

    // The charge SUCCEEDED — money is taken. Commit success now so a failure
    // of the follow-up refresh can never make a real charge look failed (which
    // would tempt staff to re-charge). The refresh is best-effort: it just
    // updates the member behind the still-open success step; the Invoices card
    // and Payment History refetch independently off the bumped refreshToken.
    // Re-read state post-await (see [_runMutation]).
    final committed = state;
    if (committed is! MemberDetailLoaded) return;
    emit(committed.copyWith(
      isChargingCard: false,
      chargeCardSuccess: committed.chargeCardSuccess + 1,
      refreshToken: committed.refreshToken + 1,
    ));
    // The invoice lands in our DB asynchronously (Stripe webhook), so
    // start the dumb 5/10/15/30/60s poll to surface it without a reload.
    _startInvoicePolling();
    try {
      final refreshed = await _repository.getMemberDetail(s.member.memberId);
      final latest = state;
      if (latest is MemberDetailLoaded) {
        emit(latest.copyWith(member: refreshed));
      }
    } catch (e, stackTrace) {
      log(
        'Charge succeeded but member refresh failed (non-fatal)',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _onChargeCardOutcomeCleared(
    ChargeCardOutcomeCleared event,
    Emitter<MemberDetailState> emit,
  ) {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    emit(s.copyWith(clearChargeOutcome: true));
  }

  Future<void> _onRefundCharge(
    RefundChargeRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    await _runMutation(
      actionLabel: 'Refund charge',
      emit: emit,
      pollInvoices: true,
      action: () => _repository.refundCharge(
        memberId: s.member.memberId,
        chargeId: event.chargeId,
        amount: event.amount,
        idempotencyKey: const Uuid().v4(),
      ),
    );
  }

  // ----- Class check-in -----

  /// The check-in dialog's mutation. Like [_onChargeCard] it rides a DEDICATED
  /// channel ([isCheckingIn] / [checkInResult] / [checkInError]) so the
  /// screen-level overlay + error dialog never fire while the dialog is open;
  /// the dialog flips to its own terminal step off the result. The CRM sends
  /// `is_member: false`: a clean check-in is recorded, any gate conditions ride
  /// along as non-blocking `warnings`; one that hits a warning is NOT recorded
  /// (`requiresConfirmation` true) unless [MemberCheckInRequested.ignoreWarnings]
  /// is set — the dialog re-dispatches with it true on "Check in anyway". Only
  /// a real recorded attendance bumps `refreshToken` (so last-class /
  /// attendance / rewards refresh) — an idempotent repeat or a
  /// needs-confirmation hold changes nothing.
  Future<void> _onCheckIn(
    MemberCheckInRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    emit(s.copyWith(
      isCheckingIn: true,
      clearCheckInOutcome: true,
    ));

    final CheckInResponse result;
    try {
      result = await _repository.checkInMember(
        CheckInRequest(
          memberId: s.member.memberId,
          gymId: s.member.gymId,
          classId: event.classId,
          occurrenceDate: _occurrenceDate.format(event.occurrenceDate),
          occurrenceTime: event.occurrenceTime,
          ignoreWarnings: event.ignoreWarnings,
        ),
      );
    } catch (e, stackTrace) {
      log('Check in failed', error: e, stackTrace: stackTrace);
      final current = state;
      if (current is! MemberDetailLoaded) return;
      emit(current.copyWith(
        isCheckingIn: false,
        checkInError: e is ServerException
            ? (e.detail ?? e.message)
            : e.toString(),
      ));
      return;
    }

    final committed = state;
    if (committed is! MemberDetailLoaded) return;
    // An idempotent repeat wrote nothing — surface the result without a
    // refresh. A fresh attendance bumps `refreshToken` so the detail surfaces
    // (last class, attendance, rewards) re-read behind the still-open dialog.
    emit(committed.copyWith(
      isCheckingIn: false,
      checkInResult: result,
      refreshToken:
          result.isRecorded ? committed.refreshToken + 1 : null,
    ));
    if (!result.isRecorded) return;

    try {
      final refreshed =
          await _repository.getMemberDetail(s.member.memberId);
      final latest = state;
      if (latest is MemberDetailLoaded) {
        emit(latest.copyWith(member: refreshed));
      }
    } catch (e, stackTrace) {
      log(
        'Check in recorded but member refresh failed (non-fatal)',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _onCheckInCleared(
    MemberCheckInCleared event,
    Emitter<MemberDetailState> emit,
  ) {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    emit(s.copyWith(clearCheckInOutcome: true));
  }

  // ----- Class reserve (sign-up) -----

  /// The check-in/reserve dialog's Reserve mutation. Rides its own DEDICATED
  /// channel ([isReserving] / [reserveResult] / [reserveError]) mirroring
  /// [_onCheckIn]'s shape. A reservation doesn't change points/attendance/
  /// billing, so — unlike check-in — there is no member-detail refresh and
  /// no `refreshToken` bump; the result is rendered straight from
  /// [SignupResponse].
  Future<void> _onReserve(
    MemberReserveRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    emit(s.copyWith(
      isReserving: true,
      clearReserveOutcome: true,
    ));

    final SignupResponse result;
    try {
      result = await _scheduleRepository.signUp(
        s.member.gymId,
        event.classId,
        event.occurrenceDate,
        event.occurrenceTime,
        s.member.memberId,
      );
    } catch (e, stackTrace) {
      log('Reserve failed', error: e, stackTrace: stackTrace);
      final current = state;
      if (current is! MemberDetailLoaded) return;
      emit(current.copyWith(
        isReserving: false,
        reserveError: e is ServerException
            ? (e.detail ?? e.message)
            : e.toString(),
      ));
      return;
    }

    final current = state;
    if (current is! MemberDetailLoaded) return;
    emit(current.copyWith(
      isReserving: false,
      reserveResult: result,
    ));
  }

  void _onReserveCleared(
    MemberReserveCleared event,
    Emitter<MemberDetailState> emit,
  ) {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    emit(s.copyWith(clearReserveOutcome: true));
  }

  // ----- Rewards / redemptions -----

  Future<void> _onApproveRedemption(
    ApproveRedemptionRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    await _runRedemptionDecision(
      actionLabel: 'Approve redemption',
      emit: emit,
      action: () => _rewardsRepository.approve(event.redemptionId),
    );
  }

  Future<void> _onRejectRedemption(
    RejectRedemptionRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    await _runRedemptionDecision(
      actionLabel: 'Reject redemption',
      emit: emit,
      action: () => _rewardsRepository.reject(event.redemptionId),
    );
  }

  /// Approve/reject share the standard mutation happy-path (act → re-fetch
  /// member detail → bump `refreshToken`) but must handle a **concurrent
  /// decision** gracefully: another staff member may have already approved
  /// or rejected the same redemption, which the repo raises as
  /// [RedemptionAlreadyDecidedException] (HTTP 409). Rather than surface the
  /// raw error and leave the now-stale row on screen, re-fetch member detail
  /// (so the decided row disappears) and set a friendly `actionError`.
  Future<void> _runRedemptionDecision({
    required String actionLabel,
    required Emitter<MemberDetailState> emit,
    required Future<void> Function() action,
  }) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;

    emit(s.copyWith(isMutating: true, clearActionError: true));

    try {
      await action();
      final refreshed = await _repository.getMemberDetail(s.member.memberId);
      final current = state;
      if (current is! MemberDetailLoaded) return;
      emit(current.copyWith(
        member: refreshed,
        isMutating: false,
        clearActionError: true,
        refreshToken: current.refreshToken + 1,
      ));
    } on RedemptionAlreadyDecidedException {
      await _refreshAfterAlreadyDecided(emit);
    } catch (e, stackTrace) {
      log('$actionLabel failed', error: e, stackTrace: stackTrace);
      final current = state;
      if (current is! MemberDetailLoaded) return;
      emit(current.copyWith(
        isMutating: false,
        actionError: e.toString(),
      ));
    }
  }

  /// Re-fetch member detail after a 409 so the already-decided pending row
  /// drops off, then surface a friendly, non-alarming message.
  Future<void> _refreshAfterAlreadyDecided(
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    const message = 'That redemption was already decided by someone '
        'else — the list has been refreshed.';
    try {
      final refreshed = await _repository.getMemberDetail(s.member.memberId);
      final current = state;
      if (current is! MemberDetailLoaded) return;
      emit(current.copyWith(
        member: refreshed,
        isMutating: false,
        actionError: message,
        refreshToken: current.refreshToken + 1,
      ));
    } catch (e, stackTrace) {
      log(
        'Refresh after already-decided redemption failed',
        error: e,
        stackTrace: stackTrace,
      );
      final current = state;
      if (current is! MemberDetailLoaded) return;
      emit(current.copyWith(isMutating: false, actionError: message));
    }
  }

  Future<void> _onRedeemRewardForMember(
    RedeemRewardForMemberRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    await _runMutation(
      actionLabel: 'Redeem reward for member',
      emit: emit,
      action: () => _repository.redeemRewardForMember(
        rewardId: event.rewardId,
        memberId: event.memberId,
        allowOverride: event.allowOverride,
      ),
    );
  }

  Future<void> _onAdjustPoints(
    AdjustPointsRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    await _runMutation(
      actionLabel: 'Adjust points',
      emit: emit,
      action: () => _repository.adjustPoints(
        memberId: event.memberId,
        amount: event.amount,
      ),
    );
  }

  // ----- Invoice polling -----

  /// Starts (or restarts) the post-charge invoice poll. Each tick is
  /// dispatched back onto the bloc so its handler can emit.
  void _startInvoicePolling() {
    _poller.start(() {
      if (!isClosed) add(const InvoicePollRequested());
    });
  }

  /// One poll tick: a dumb re-read of the billing surfaces. Re-fetches
  /// member detail and bumps `refreshToken` (exactly like a mutation's
  /// success tail) so the Invoices card and Payment history re-load and
  /// a webhook-delivered invoice appears. No "did an invoice arrive"
  /// check. The refresh is best-effort — on a fetch failure the token
  /// is still bumped so the self-fetching sections retry their own
  /// reads.
  Future<void> _onInvoicePoll(
    InvoicePollRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    final seq = ++_pollSeq;
    try {
      final refreshed = await _repository.getMemberDetail(
        s.member.memberId,
      );
      // A newer tick started while this one's fetch was in flight —
      // drop this (now older) result so it can't overwrite the fresher
      // one.
      if (seq != _pollSeq) return;
      final current = state;
      if (current is MemberDetailLoaded) {
        emit(current.copyWith(
          member: refreshed,
          refreshToken: current.refreshToken + 1,
        ));
      }
    } catch (e, stackTrace) {
      log(
        'Invoice poll refresh failed (non-fatal)',
        error: e,
        stackTrace: stackTrace,
      );
      if (seq != _pollSeq) return;
      final current = state;
      if (current is MemberDetailLoaded) {
        emit(current.copyWith(
          refreshToken: current.refreshToken + 1,
        ));
      }
    }
  }

  /// Apply a rank change (promote / set / unassign) via the ranks
  /// domain, then reload member detail in place — new rank + real
  /// progress, bumping refreshToken, same shape as a mutation.
  Future<void> _onRankChange(
    MemberRankChangeRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final current = state;
    if (current is! MemberDetailLoaded) return;
    emit(current.copyWith(isMutating: true));
    final gymId = current.member.gymId;
    final memberId = current.member.memberId;
    try {
      if (event.promote) {
        await _ranksRepository.promoteMember(gymId, memberId);
      } else {
        await _ranksRepository.setMemberRank(gymId, memberId, event.rankId);
      }
      final refreshed = await _repository.getMemberDetail(memberId);
      final latest = state;
      if (latest is MemberDetailLoaded) {
        emit(latest.copyWith(
          member: refreshed,
          isMutating: false,
          refreshToken: latest.refreshToken + 1,
        ));
      }
    } catch (e, stackTrace) {
      log('Rank change failed', error: e, stackTrace: stackTrace);
      final latest = state;
      if (latest is MemberDetailLoaded) {
        emit(latest.copyWith(
          isMutating: false,
          actionError: e.toString(),
        ));
      }
    }
  }

  @override
  Future<void> close() {
    _poller.cancel();
    return super.close();
  }
}
