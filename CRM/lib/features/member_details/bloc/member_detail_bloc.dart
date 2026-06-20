import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/member_memberships_freeze_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_mark_paid_cash_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_unfreeze_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_add_discounts_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_remove_discounts_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_update_price_request.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';

/// BLoC for the Specific Member Detail screen.
class MemberDetailBloc
    extends Bloc<MemberDetailEvent, MemberDetailState> {
  final MemberRepository _repository;

  MemberDetailBloc({
    required MemberRepository repository,
  })  : _repository = repository,
        super(const MemberDetailInitial()) {
    on<MemberDetailRequested>(_onDetailRequested);
    on<MemberSearchChanged>(_onSearchChanged);
    on<MembershipPageChanged>(_onPageChanged);
    on<MemberActionErrorCleared>(_onActionErrorCleared);

    on<EditMemberRequested>(_onEditMember);
    on<UpdateCardRequested>(_onUpdateCard);
    on<UnlinkPaymentRequested>(_onUnlinkPayment);
    on<LinkParentRequested>(_onLinkParent);
    on<UnlinkParentRequested>(_onUnlinkParent);

    on<StartMembershipsRequested>(_onStartMemberships);
    on<StartMembershipsCleared>(
      _onStartMembershipsCleared,
    );
    on<CancelMembershipRequested>(_onCancelMembership);
    on<UpdatePriceRequested>(_onUpdatePrice);
    on<FreezeAccountRequested>(_onFreezeAccount);
    on<UnfreezeAccountRequested>(_onUnfreezeAccount);
    on<MarkPaidCashRequested>(_onMarkPaidCash);

    on<AddDiscountsRequested>(_onAddDiscounts);
    on<RemoveDiscountsRequested>(_onRemoveDiscounts);

    on<ChargeCardRequested>(_onChargeCard);
    on<ChargeCardOutcomeCleared>(_onChargeCardOutcomeCleared);
    on<RefundChargeRequested>(_onRefundCharge);
  }

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
  Future<void> _runMutation({
    required String actionLabel,
    required Emitter<MemberDetailState> emit,
    required Future<void> Function() action,
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
      emit(s.copyWith(
        member: refreshed,
        isMutating: false,
        clearActionError: true,
        refreshToken: s.refreshToken + 1,
      ));
    } catch (e, stackTrace) {
      log(
        '$actionLabel failed',
        error: e,
        stackTrace: stackTrace,
      );
      emit(s.copyWith(
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
      actionLabel: 'Link parent',
      emit: emit,
      action: () => _repository.linkMemberAccount(
        event.childMemberId ?? s.member.memberId,
        event.parentMemberId,
      ),
    );
  }

  Future<void> _onUnlinkParent(
    UnlinkParentRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    await _runMutation(
      actionLabel: 'Unlink parent',
      emit: emit,
      action: () => _repository.unlinkMemberAccount(
        event.childMemberId ?? s.member.memberId,
      ),
    );
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
      emit(s.copyWith(
        member: refreshed,
        isStartingMemberships: false,
        startResult: result,
        refreshToken: s.refreshToken + 1,
      ));
    } catch (e, stackTrace) {
      log(
        'Start memberships failed',
        error: e,
        stackTrace: stackTrace,
      );
      emit(s.copyWith(
        isStartingMemberships: false,
        startError: e is ServerException
            ? (e.detail ?? e.message)
            : e.toString(),
      ));
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

  Future<void> _onCancelMembership(
    CancelMembershipRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    await _runMutation(
      actionLabel: 'Cancel membership',
      emit: emit,
      action: () => _repository.cancelMembership(
        itemId: event.itemId,
        memberId: event.memberId,
        idempotencyKey: const Uuid().v4(),
      ),
    );
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
          prorate: event.prorate,
          idempotencyKey: const Uuid().v4(),
        ),
      ),
    );
  }

  Future<void> _onFreezeAccount(
    FreezeAccountRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    final s = state;
    if (s is! MemberDetailLoaded) return;
    await _runMutation(
      actionLabel: 'Freeze account',
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
      actionLabel: 'Unfreeze account',
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
      final refreshed = await _repository.getMemberDetail(
        s.member.memberId,
      );
      emit(s.copyWith(
        member: refreshed,
        isChargingCard: false,
        chargeCardSuccess: s.chargeCardSuccess + 1,
        refreshToken: s.refreshToken + 1,
      ));
    } catch (e, stackTrace) {
      log(
        'Charge card failed',
        error: e,
        stackTrace: stackTrace,
      );
      emit(s.copyWith(
        isChargingCard: false,
        chargeCardError: e is ServerException
            ? (e.detail ?? e.message)
            : e.toString(),
      ));
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
      action: () => _repository.refundCharge(
        memberId: s.member.memberId,
        chargeId: event.chargeId,
        amount: event.amount,
      ),
    );
  }
}
