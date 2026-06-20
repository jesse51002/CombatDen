import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_payment.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/member_summary.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_card_capture.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/membership_draft.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/one_time_card_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_link_member_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_footer.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_step_body.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_wizard_helpers.dart';
import 'package:crm/features/member_details/presentation/dialogs/update_card_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';

/// The Start Memberships wizard — one request per run:
/// 1. who pays (any family member — the top-level account
///    pays for the family; a linked member self-pays),
/// 2. who's getting memberships (payer + linked members),
/// 3. per member: pick plans (count stepper on one_time /
///    trial),
/// 4. per member: discounts per membership (presets +
///    inline customs via the picker),
/// 5. review — who's getting what (pure content, no
///    prices),
/// 6. the server-side charge preview (navigation only),
/// 7. payment (card on file / REAL cash toggle) — PAY is
///    the single trigger that sends
///    `POST /api/v1/member_memberships/`,
/// 8. the per-membership created/failed breakdown.
///
/// A single member buying one plan is the same path with
/// the payer pre-selected and one loop iteration — no
/// separate code path.
class StartMembershipsWizard extends StatefulWidget {
  final MemberDetailResponse member;

  /// Navigates to another member's detail page — backs the
  /// results step's "view member" link on created rows.
  final ValueChanged<String>? onViewMember;

  const StartMembershipsWizard({
    super.key,
    required this.member,
    this.onViewMember,
  });

  static Future<void> show({
    required BuildContext context,
    required MemberDetailResponse member,
    ValueChanged<String>? onViewMember,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: StartMembershipsWizard(
          member: member,
          onViewMember: onViewMember,
        ),
      ),
    );
  }

  @override
  State<StartMembershipsWizard> createState() =>
      _StartMembershipsWizardState();
}

class _StartMembershipsWizardState
    extends State<StartMembershipsWizard> {
  final MemberRepository _repository =
      MemberRepository(apiClient: ApiClient());

  late final MemberDetailBloc _bloc;
  late StartMembershipParticipant _payer;
  MemberDetailResponse? _payerDetail;

  var _step = StartMembershipsStep.payer;
  int _memberIndex = 0;
  final Set<String> _selectedMemberIds = {};
  final Map<String, List<MembershipDraft>> _drafts = {};

  /// Full member details keyed by member id, best-effort,
  /// so plan-tile rules resolve per configured member.
  final Map<String, MemberDetailResponse>
      _memberDetails = {};

  late final Future<List<MembershipPlanResponse>>
      _plansFuture;
  late final _discountsFuture =
      _repository.listGymDiscounts(widget.member.gymId);

  bool _prorate = true;
  bool _paidWithCash = false;

  /// A one-off card captured for the one-time charge (null =
  /// the saved default pays it). Kept across a cash toggle;
  /// only carried on PAY when not paying cash.
  CustomCardCapture? _customCard;

  /// True while editing one member's lineup from review —
  /// the discounts step then returns straight to review.
  bool _editReturnsToReview = false;
  MemberMembershipsStartRequest? _previewRequest;
  MemberMembershipsStartPreview? _preview;

  @override
  void initState() {
    super.initState();
    _bloc = context.read<MemberDetailBloc>();
    // Clear any breakdown from a prior run on open — the only
    // consumer of the start result is this wizard, so a fresh
    // open always starts clean. We deliberately do NOT dispatch
    // on dispose: emitting while the dialog's own BlocProvider /
    // BlocBuilder tears down raced the widget teardown and threw
    // a `_dependents.isEmpty` assertion on close.
    _bloc.add(const StartMembershipsCleared());
    _plansFuture =
        _repository.listMembershipPlans(widget.member.gymId);
    _initPayer();
  }

  /// The DEFAULT payer is the top-level paying account: the
  /// viewed member when they are not linked to anyone,
  /// otherwise the account they are linked to. The payer
  /// step lets staff switch to any family member (a linked
  /// member self-pays their own memberships).
  void _initPayer() {
    final viewed = widget.member;
    final parentId = viewed.linkedToAccount;
    _memberDetails[viewed.memberId] = viewed;
    if (parentId == null) {
      _payer = StartMembershipParticipant(
        memberId: viewed.memberId,
        name: viewed.fullName,
        photoUrl: viewed.photoUrl,
        isPayer: true,
      );
      _payerDetail = viewed;
      // The payer's own page already carries their detail, but the
      // linked children's details still need fetching — without this
      // the children's "Already has" block and already-on-plan guard
      // silently have no data in the payer-launched flow.
      _loadFamilyDetails(viewed);
    } else {
      final parents = viewed.linkedAccounts
          .where((a) => a.memberId == parentId);
      _payer = StartMembershipParticipant(
        memberId: parentId,
        name: parents.isEmpty
            ? 'Paying account'
            : parents.first.fullName,
        photoUrl: parents.isEmpty
            ? null
            : parents.first.photoUrl,
        isPayer: true,
      );
      _loadPayerDetail();
    }
    // Sensible default: the member whose page launched the
    // wizard is getting the membership.
    _selectedMemberIds.add(viewed.memberId);
  }

  Future<void> _loadPayerDetail({
    String? alsoSelect,
  }) async {
    try {
      final detail = await _repository
          .getMemberDetail(_payer.memberId);
      if (!mounted) return;
      setState(() {
        _payerDetail = detail;
        _memberDetails[detail.memberId] = detail;
        if (alsoSelect != null) {
          _selectedMemberIds.add(alsoSelect);
        }
      });
      _loadFamilyDetails(detail);
    } catch (_) {
      // Best-effort; the members step keeps its spinner
      // and staff can back out. The backend remains the
      // source of truth either way.
    }
  }

  /// Best-effort detail per linked member so the plan step
  /// can disable plans they already actively hold.
  Future<void> _loadFamilyDetails(
    MemberDetailResponse payerDetail,
  ) async {
    for (final a in payerDetail.linkedAccounts) {
      if (_memberDetails.containsKey(a.memberId)) {
        continue;
      }
      try {
        final detail =
            await _repository.getMemberDetail(a.memberId);
        if (!mounted) return;
        setState(
          () => _memberDetails[a.memberId] = detail,
        );
      } catch (_) {
        // Missing data just means no inline plan warnings
        // for that member — the backend still rejects
        // duplicates.
      }
    }
  }

  // ----- Derived (free functions in the helpers) -----

  List<StartMembershipParticipant> get _configMembers =>
      configMembersFor(
        payer: _payer,
        payerDetail: _payerDetail,
        selectedMemberIds: _selectedMemberIds,
      );

  StartMembershipParticipant? get _currentMember =>
      currentMemberOf(_configMembers, _memberIndex);

  List<MembershipDraft> get _currentDrafts =>
      _drafts[_currentMember?.memberId] ?? const [];

  bool get _hasRecurring =>
      hasRecurringDrafts(_configMembers, _drafts);

  bool get _hasOneTime =>
      hasOneTimeDrafts(_configMembers, _drafts);

  /// The wire request. The one-off card rides on PAY only
  /// ([forPay]) — never on a preview — and only when paying
  /// by card for a PURELY one-time cart (no recurring, which
  /// always bills the saved default).
  MemberMembershipsStartRequest? _buildRequest(
    String idempotencyKey, {
    bool forPay = false,
  }) {
    final card = _customCard;
    final useCard = forPay &&
        !_paidWithCash &&
        _hasOneTime &&
        !_hasRecurring &&
        card != null;
    return buildStartRequest(
      idempotencyKey: idempotencyKey,
      payerMemberId: _payer.memberId,
      gymId: widget.member.gymId,
      prorate: _prorate,
      paidWithCash: _paidWithCash,
      configMembers: _configMembers,
      drafts: _drafts,
      // A one-off card is never saved as the default (set_default
      // stays false) — it pays today's one-time invoice only.
      payment: useCard
          ? MemberMembershipsStartPayment(
              paymentMethodId: card.pmId,
            )
          : null,
    );
  }

  // ----- Step transitions -----

  void _next() {
    setState(() {
      switch (_step) {
        case StartMembershipsStep.payer:
          _step = StartMembershipsStep.members;
        case StartMembershipsStep.members:
          _memberIndex = 0;
          _step = StartMembershipsStep.plans;
        case StartMembershipsStep.plans:
          _step = StartMembershipsStep.discounts;
        case StartMembershipsStep.discounts:
          if (_editReturnsToReview) {
            // Finished editing this one member — straight
            // back to review, no walk to the next member.
            _editReturnsToReview = false;
            _step = StartMembershipsStep.review;
          } else if (_memberIndex + 1 <
              _configMembers.length) {
            _memberIndex++;
            _step = StartMembershipsStep.plans;
          } else {
            _step = StartMembershipsStep.review;
          }
        case StartMembershipsStep.review:
          _enterPreview();
        case StartMembershipsStep.preview:
          // Confirm = navigation only; PAY fires the one
          // mutation on the payment step.
          _step = StartMembershipsStep.payment;
        case StartMembershipsStep.payment:
        case StartMembershipsStep.results:
          break;
      }
    });
  }

  void _back() {
    setState(() {
      switch (_step) {
        case StartMembershipsStep.payer:
        case StartMembershipsStep.results:
          break;
        case StartMembershipsStep.members:
          _step = StartMembershipsStep.payer;
        case StartMembershipsStep.plans:
          if (_editReturnsToReview) {
            // Back mid-edit abandons the edit and returns
            // to review.
            _editReturnsToReview = false;
            _step = StartMembershipsStep.review;
          } else if (_memberIndex == 0) {
            _step = StartMembershipsStep.members;
          } else {
            _memberIndex--;
            _step = StartMembershipsStep.discounts;
          }
        case StartMembershipsStep.discounts:
          _step = StartMembershipsStep.plans;
        case StartMembershipsStep.review:
          _memberIndex = _configMembers.length - 1;
          _step = StartMembershipsStep.discounts;
        case StartMembershipsStep.preview:
          _step = StartMembershipsStep.review;
        case StartMembershipsStep.payment:
          _enterPreview();
      }
    });
  }

  void _enterPreview() {
    // The preview stages the SAME request shape; its key
    // is a throwaway (PAY mints a fresh one).
    _previewRequest = _buildRequest(const Uuid().v4());
    _preview = null;
    _step = StartMembershipsStep.preview;
  }

  void _onPay() {
    // The idempotency key is generated at PAY press; a
    // retry of the same press dedups at Stripe.
    final req = _buildRequest(const Uuid().v4(), forPay: true);
    if (req == null) return;
    _bloc.add(StartMembershipsRequested(req));
    setState(
      () => _step = StartMembershipsStep.results,
    );
  }

  /// "Retry the failed memberships" = a NEW request with
  /// only the failed items and a new idempotency key.
  void _onRetryFailed() {
    final s = _bloc.state;
    if (s is! MemberDetailLoaded) return;
    final result = s.startResult;
    if (result == null) return;
    final items = retryItemsFor(result.failed, _drafts);
    if (items.isEmpty) return;
    // A retry re-bills the same one-off card (Stripe keeps it
    // attached after a decline so it can be reused) — only for
    // a purely one-time cart, the only shape that can hold a
    // custom card.
    final card = _customCard;
    final useCard = !_paidWithCash &&
        _hasOneTime &&
        !_hasRecurring &&
        card != null;
    _bloc.add(StartMembershipsRequested(
      MemberMembershipsStartRequest(
        payerMemberId: _payer.memberId,
        gymId: widget.member.gymId,
        idempotencyKey: const Uuid().v4(),
        prorate: _prorate,
        paidWithCash: _paidWithCash,
        payment: useCard
            ? MemberMembershipsStartPayment(
                paymentMethodId: card.pmId,
              )
            : null,
        memberships: items,
      ),
    ));
  }

  /// Prorate changes the due-now amount, so the totals
  /// echoed on the payment step are re-previewed (still a
  /// dry run — nothing committed).
  void _onProrateChanged(bool v) {
    setState(() {
      _prorate = v;
      _preview = null;
      _previewRequest =
          _buildRequest(const Uuid().v4());
    });
    final req = _previewRequest;
    if (req == null) return;
    _repository
        .previewStartMemberships(req)
        .then((p) {
      if (mounted && _prorate == v) {
        setState(() => _preview = p);
      }
    }).catchError((_) {
      // The echo stays empty; the preview step remains
      // the authoritative reload path.
    });
  }

  /// "View member" on a created result row: close the
  /// wizard (the page behind has refreshed) and, for a
  /// member other than the viewed one, navigate to their
  /// detail page via the caller's navigation callback.
  void _onViewMember(String memberId) {
    Navigator.of(context).pop();
    if (memberId != widget.member.memberId) {
      widget.onViewMember?.call(memberId);
    }
  }

  // ----- Review-step edit / remove -----

  /// Edit one member's lineup: jump back into their plans
  /// step; the discounts step then returns to review.
  void _onEditMember(String memberId) {
    final i = _configMembers
        .indexWhere((m) => m.memberId == memberId);
    if (i < 0) return;
    setState(() {
      _memberIndex = i;
      _editReturnsToReview = true;
      _step = StartMembershipsStep.plans;
    });
  }

  /// Remove one membership draft from review. When it was the
  /// member's last draft, drop the member from the run too.
  void _onRemoveDraft(String memberId, String planId) {
    setState(() {
      final remaining = [
        for (final d in _drafts[memberId] ?? const <MembershipDraft>[])
          if (d.plan.planId != planId) d,
      ];
      if (remaining.isEmpty) {
        _drafts.remove(memberId);
        _selectedMemberIds.remove(memberId);
      } else {
        _drafts[memberId] = remaining;
      }
    });
  }

  // ----- One-off card (one-time charge) -----

  Future<void> _onAddOrChangeCustomCard() async {
    // A pure one-off — never saved, never the default. It pays
    // today's one-time invoice once; no card on file is needed.
    final captured = await OneTimeCardDialog.show(
      context: context,
    );
    if (captured == null || !mounted) return;
    setState(() => _customCard = captured);
  }

  void _onRemoveCustomCard() {
    setState(() => _customCard = null);
  }

  // ----- Selection mutations -----

  /// Switching the payer restarts the selection under the
  /// new payer: who can be covered depends on who pays
  /// (the backend's self-or-parent rule), so stale picks
  /// and drafts are cleared and the payer's own detail is
  /// (re)loaded for the members step.
  void _onPayerSelected(StartMembershipParticipant p) {
    if (p.memberId == _payer.memberId) return;
    setState(() {
      _payer = StartMembershipParticipant(
        memberId: p.memberId,
        name: p.name,
        photoUrl: p.photoUrl,
        isPayer: true,
      );
      _payerDetail = _memberDetails[p.memberId];
      _selectedMemberIds
        ..clear()
        ..add(p.memberId);
      _drafts.clear();
      _preview = null;
      _previewRequest = null;
    });
    if (_payerDetail == null) {
      _loadPayerDetail();
    }
  }

  void _onMemberToggle(String memberId) {
    setState(() {
      if (!_selectedMemberIds.remove(memberId)) {
        _selectedMemberIds.add(memberId);
      } else {
        _drafts.remove(memberId);
      }
    });
  }

  void _onPlanToggle(MembershipPlanResponse plan) {
    final memberId = _currentMember?.memberId;
    if (memberId == null) return;
    setState(() {
      _drafts[memberId] = draftsWithPlanToggled(
        _drafts[memberId] ?? const [],
        plan,
      );
    });
  }

  void _updateDraft(
    String planId,
    MembershipDraft Function(MembershipDraft) change,
  ) {
    final memberId = _currentMember?.memberId;
    if (memberId == null) return;
    setState(() {
      _drafts[memberId] = [
        for (final d in _drafts[memberId] ?? const <MembershipDraft>[])
          if (d.plan.planId == planId) change(d) else d,
      ];
    });
  }

  // ----- Link-first + add-card jumps -----

  Future<void> _onLinkFirst() async {
    final s = _bloc.state;
    final roster = s is MemberDetailLoaded
        ? s.allMembers
        : const <MemberSummary>[];
    final family = <String>{
      _payer.memberId,
      ...?_payerDetail?.linkedAccounts
          .map((a) => a.memberId),
    };
    final candidates = roster
        .where((m) => !family.contains(m.memberId))
        .toList();
    final tokenBefore =
        s is MemberDetailLoaded ? s.refreshToken : -1;
    final linkedId = await StartLinkMemberDialog.show(
      context: context,
      payerMemberId: _payer.memberId,
      payerName: _payer.name,
      candidates: candidates,
    );
    if (linkedId == null || !mounted) return;
    await _awaitBlocSettle(tokenBefore);
    if (!mounted) return;
    await _loadPayerDetail(alsoSelect: linkedId);
  }

  Future<void> _onAddNewCard() async {
    // The saved card always belongs to the PAYER. Target
    // them explicitly so it can be added/replaced from any
    // launching page (e.g. a linked child's), then re-read
    // the payer detail once the mutation lands.
    final s = _bloc.state;
    final tokenBefore =
        s is MemberDetailLoaded ? s.refreshToken : -1;
    await UpdateCardDialog.show(
      context: context,
      memberName: _payer.name,
      card: _payerDetail?.cardOnFile,
      targetMemberId: _payer.memberId,
      // Removing a card mid-checkout makes no sense; removal
      // lives on the member profile behind its own confirmation.
      allowRemove: false,
    );
    if (!mounted) return;
    await _awaitBlocSettle(tokenBefore);
    if (!mounted) return;
    await _loadPayerDetail();
  }

  /// Waits for an in-flight bloc mutation (link / card
  /// update) to land before re-reading the payer detail.
  Future<void> _awaitBlocSettle(int tokenBefore) async {
    try {
      await _bloc.stream
          .firstWhere(
            (st) =>
                st is MemberDetailLoaded &&
                !st.isMutating &&
                (st.refreshToken != tokenBefore ||
                    st.actionError != null),
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      // Timed out / stream closed — fall through to the
      // refetch; worst case the family list is briefly
      // stale.
    }
  }

  // ----- Footer -----

  bool get _canAdvance {
    switch (_step) {
      case StartMembershipsStep.payer:
        return true;
      case StartMembershipsStep.members:
        return _payerDetail != null &&
            _selectedMemberIds.isNotEmpty;
      case StartMembershipsStep.plans:
        return _currentDrafts.isNotEmpty;
      case StartMembershipsStep.discounts:
        return true;
      case StartMembershipsStep.review:
        // At least one draft must remain (remove can empty
        // the lineup entirely).
        return _configMembers.any(
          (m) =>
              (_drafts[m.memberId] ?? const []).isNotEmpty,
        );
      case StartMembershipsStep.preview:
        return _previewRequest != null;
      case StartMembershipsStep.payment:
        // Cash, a saved card, or — for a one-time-only cart
        // with no saved card — the one-off card alone.
        return _paidWithCash ||
            _payerDetail?.cardOnFile != null ||
            (!_hasRecurring && _customCard != null);
      case StartMembershipsStep.results:
        return !_isStarting;
    }
  }

  bool get _isStarting {
    final s = _bloc.state;
    return s is MemberDetailLoaded &&
        s.isStartingMemberships;
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the footer while the start POST is in
    // flight / lands (the results step body listens on
    // its own).
    return BlocBuilder<MemberDetailBloc,
        MemberDetailState>(
      buildWhen: (prev, curr) =>
          _step == StartMembershipsStep.results,
      builder: (context, _) {
        return AppDialog(
          title: 'Start memberships',
          // A workflow surface, not a confirmation box:
          // a generous viewport fraction with a fixed
          // stepper/header and footer; the step content
          // scrolls in between.
          expanded: true,
          maxWidth: DesignConstants.dialogMaxWidthWide,
          contentPadding: const EdgeInsets.all(
            DesignConstants.paddingBig,
          ),
          body: StartMembershipsStepBody(
            step: _step,
            launchMember: widget.member,
            repository: _repository,
            payer: _payer,
            payerDetail: _payerDetail,
            currentMember: _currentMember,
            selectedMemberIds: _selectedMemberIds,
            currentDrafts: _currentDrafts,
            configMembers: _configMembers,
            draftsByMember: _drafts,
            disabledPlanReasons: disabledPlanReasonsFor(
              _currentMember,
              _memberDetails,
            ),
            existingMemberships: existingMembershipsFor(
              _currentMember,
              _memberDetails,
            ),
            plansFuture: _plansFuture,
            discountsFuture: _discountsFuture,
            previewRequest: _previewRequest,
            preview: _preview,
            prorate: _prorate,
            paidWithCash: _paidWithCash,
            hasRecurring: _hasRecurring,
            hasOneTime: _hasOneTime,
            customCard: _customCard,
            payerCardOnFile: _payerDetail?.cardOnFile,
            memberNames: memberNamesOf(_configMembers),
            planNames: planNamesOf(_drafts),
            onPayerSelected: _onPayerSelected,
            onMemberToggle: _onMemberToggle,
            onLinkFirst: _onLinkFirst,
            onPlanToggle: _onPlanToggle,
            onDraftChanged: _updateDraft,
            onPreviewLoaded: (p) =>
                setState(() => _preview = p),
            onProrateChanged: _onProrateChanged,
            onPaidWithCashChanged: (v) =>
                setState(() => _paidWithCash = v),
            onAddNewCard: _onAddNewCard,
            onAddOrChangeCustomCard:
                _onAddOrChangeCustomCard,
            onRemoveCustomCard: _onRemoveCustomCard,
            onEditMember: _onEditMember,
            onRemoveDraft: _onRemoveDraft,
            onRetryFailed: _onRetryFailed,
            onViewMember: _onViewMember,
            onBackToPayment: () => setState(
              () =>
                  _step = StartMembershipsStep.payment,
            ),
          ),
          actions: StartMembershipsFooter(
            step: _step,
            hasNextMember: _memberIndex + 1 <
                _configMembers.length,
            isEditing: _editReturnsToReview,
            canAdvance: _canAdvance,
            isStarting: _isStarting,
            onNext: _next,
            onPay: _onPay,
            onBack: _back,
          ),
        );
      },
    );
  }
}
