import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/linked_account.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_payment.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/member_summary.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/authorize_direction.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_card_capture.dart';
import 'package:crm/features/member_details/presentation/dialogs/member_detail_bloc_settle.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/membership_draft.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/one_time_card_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_link_member_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_new_member_dialog.dart';
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

  /// Shows the leading "Add member" group in the step indicator and shifts the
  /// "Step N of M" numbering by one — true only when the wizard is embedded in
  /// the add-member flow (the create already happened). Member-detail launches
  /// leave it false, so that context stays exactly three groups.
  final bool showAddMemberGroup;

  /// Seeds which members start selected on the "who joins" step. The add-member
  /// group flow passes the whole group's ids (payer included) so everyone the
  /// payer just authorized is pre-checked. Null (detail-page launches) falls
  /// back to selecting only the viewed member.
  final Set<String>? initialSelectedMemberIds;

  const StartMembershipsWizard({
    super.key,
    required this.member,
    this.onViewMember,
    this.showAddMemberGroup = false,
    this.initialSelectedMemberIds,
  });

  static Future<void> show({
    required BuildContext context,
    required MemberDetailResponse member,
    ValueChanged<String>? onViewMember,
    bool showAddMemberGroup = false,
    Set<String>? initialSelectedMemberIds,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: StartMembershipsWizard(
          member: member,
          onViewMember: onViewMember,
          showAddMemberGroup: showAddMemberGroup,
          initialSelectedMemberIds: initialSelectedMemberIds,
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

  /// The payer-step candidate list — the launch member's authorized payers.
  /// Seeded from the immutable [widget.member] snapshot and refreshed from the
  /// reloaded launch member after a new payer is authorized in-flow.
  late List<LinkedAccount> _payerCandidates;

  var _step = StartMembershipsStep.payer;
  int _memberIndex = 0;
  final Set<String> _selectedMemberIds = {};
  final Map<String, List<MembershipDraft>> _drafts = {};

  /// Non-null while on the [StartMembershipsStep.signWaivers] step.
  WaiverGateException? _waiverGate;
  bool _waiversAllSigned = false;

  /// Full member details keyed by member id, best-effort,
  /// so plan-tile rules resolve per configured member.
  final Map<String, MemberDetailResponse>
      _memberDetails = {};

  late final Future<List<MembershipPlanResponse>>
      _plansFuture;
  late final _discountsFuture =
      _repository.listGymDiscounts(widget.member.gymId);

  ProrationBehavior _prorationBehavior =
      ProrationBehavior.prorateToAnchor;
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

  /// The DEFAULT payer is the viewed member (self-pay). The payer
  /// step lets staff switch to any of the member's authorized payers
  /// (a member may have many).
  void _initPayer() {
    final viewed = widget.member;
    _memberDetails[viewed.memberId] = viewed;
    _payer = StartMembershipParticipant(
      memberId: viewed.memberId,
      name: viewed.fullName,
      photoUrl: viewed.photoUrl,
      isPayer: true,
    );
    _payerDetail = viewed;
    _payerCandidates = viewed.authorizedPayers;
    // The viewed member's own page already carries their detail, but
    // the details of the people they may pay for still need fetching —
    // without this the "Already has" block and already-on-plan guard
    // silently have no data in the payer-launched flow.
    _loadFamilyDetails(viewed);
    // Sensible default: the member whose page launched the wizard is getting
    // the membership. The add-member group flow overrides this with the whole
    // group (payer + everyone the payer just authorized).
    final initial = widget.initialSelectedMemberIds;
    if (initial != null && initial.isNotEmpty) {
      _selectedMemberIds.addAll(initial);
    } else {
      _selectedMemberIds.add(viewed.memberId);
    }
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
    for (final a in payerDetail.authorizedToPayFor) {
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
    ProrationBehavior? prorationOverride,
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
      prorationBehavior: prorationOverride ?? _prorationBehavior,
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
        case StartMembershipsStep.signWaivers:
          // Waivers signed — re-enter the preview so the now-ungated
          // charge breakdown loads before payment (the gate is caught
          // at the preview call, so the preview was never shown).
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
        case StartMembershipsStep.signWaivers:
          // Back from waiver gate — return to review to change
          // the selection. Clear gate so re-entering next is clean.
          _waiverGate = null;
          _waiversAllSigned = false;
          _step = StartMembershipsStep.review;
        case StartMembershipsStep.preview:
          _step = StartMembershipsStep.review;
        case StartMembershipsStep.payment:
          _enterPreview();
      }
    });
  }

  void _enterPreview() {
    // The preview stages the SAME request shape; its key is a
    // throwaway (PAY mints a fresh one). It is ALWAYS previewed at
    // `prorate_to_anchor` so the response carries the full split
    // (due_now + recurring). Toggling the proration choice on the
    // preview step then suppresses due_now locally — no re-fetch —
    // because `no_charge` is exactly this split minus due_now (the
    // recurring/one-time figures are identical). PAY still submits
    // the chosen `_prorationBehavior`.
    _previewRequest = _buildRequest(
      const Uuid().v4(),
      prorationOverride: ProrationBehavior.prorateToAnchor,
    );
    _preview = null;
    _step = StartMembershipsStep.preview;
  }

  /// Routes the wizard to the sign-waivers step for a 422 waiver
  /// gate. Shared by the PAY-path bloc listener (the backstop) and
  /// the preview step's direct-call gate (the proactive block before
  /// payment).
  void _routeToSignWaivers(WaiverGateException gate) {
    setState(() {
      _waiverGate = gate;
      _waiversAllSigned = false;
      _step = StartMembershipsStep.signWaivers;
    });
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
        prorationBehavior: _prorationBehavior,
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

  /// The proration choice (selected ON the preview step) only
  /// changes WHICH already-fetched lines show: the preview was
  /// loaded once with the full split (due_now + recurring), so a
  /// toggle is a pure local re-derive (due_now suppressed for
  /// no_charge) — NO request rebuild and NO re-fetch, so the
  /// breakdown never blanks. PAY submits the chosen behavior.
  void _onProrationChanged(ProrationBehavior v) {
    setState(() {
      _prorationBehavior = v;
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
      // Auto-select the member whose page launched the wizard (always a valid
      // participant for any chosen payer — the payer choices are that member's
      // authorized payers), not the newly-chosen payer.
      _selectedMemberIds
        ..clear()
        ..add(widget.member.memberId);
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
      ...?_payerDetail?.authorizedToPayFor
          .map((a) => a.memberId),
    };
    final candidates = roster
        .where((m) => !family.contains(m.memberId))
        .toList();
    final tokenBefore =
        s is MemberDetailLoaded ? s.refreshToken : -1;
    final linkedId = await StartLinkMemberDialog.show(
      context: context,
      direction: AuthorizeDirection.addPayee,
      anchorMemberId: _payer.memberId,
      anchorName: _payer.name,
      candidates: candidates,
    );
    if (linkedId == null || !mounted) return;
    await awaitMemberDetailSettle(_bloc, tokenBefore);
    if (!mounted) return;
    await _loadPayerDetail(alsoSelect: linkedId);
  }

  /// "New member" adder: create someone new (or reuse an existing duplicate)
  /// and authorize the payer for them, then add them to this run. When the
  /// dialog committed an authorization it mirrors [_onLinkFirst]'s sequencing;
  /// a direct select of an already-authorized member just adds them.
  Future<void> _onNewMember() async {
    final s = _bloc.state;
    final tokenBefore =
        s is MemberDetailLoaded ? s.refreshToken : -1;
    final authorizedIds = <String>{
      _payer.memberId,
      ...?_payerDetail?.authorizedToPayFor
          .map((a) => a.memberId),
    };
    final result = await StartNewMemberDialog.show(
      context: context,
      direction: AuthorizeDirection.addPayee,
      anchorMemberId: _payer.memberId,
      anchorName: _payer.name,
      gymId: widget.member.gymId,
      relatedIds: authorizedIds,
    );
    if (result == null || !mounted) return;
    if (result.committedLink) {
      await awaitMemberDetailSettle(_bloc, tokenBefore);
      if (!mounted) return;
      await _loadPayerDetail(alsoSelect: result.memberId);
    } else {
      // Already authorized — just include them in the run.
      setState(() => _selectedMemberIds.add(result.memberId));
    }
  }

  /// "New member" adder on the PAYER step (inverse of [_onNewMember]): create
  /// someone new (or reuse a duplicate) and authorize THEM as a payer for the
  /// launch member (the payee). On a committed authorization it mirrors
  /// [_onNewMember]'s sequencing, then refreshes the payer candidates and
  /// auto-selects the added payer; a direct select of an already-authorized
  /// payer just selects them.
  Future<void> _onNewPayer() async {
    final s = _bloc.state;
    final tokenBefore =
        s is MemberDetailLoaded ? s.refreshToken : -1;
    final relatedIds = <String>{
      widget.member.memberId,
      ..._payerCandidates.map((a) => a.memberId),
    };
    final result = await StartNewMemberDialog.show(
      context: context,
      direction: AuthorizeDirection.addPayer,
      anchorMemberId: widget.member.memberId,
      anchorName: widget.member.fullName,
      gymId: widget.member.gymId,
      relatedIds: relatedIds,
    );
    if (result == null || !mounted) return;
    if (result.committedLink) {
      await awaitMemberDetailSettle(_bloc, tokenBefore);
      if (!mounted) return;
      _refreshPayerCandidates(select: result.memberId);
    } else {
      // Already an authorized payer (or the launch member) — just select them.
      _selectPayerById(result.memberId);
    }
  }

  /// "Link someone" adder on the PAYER step (inverse of [_onLinkFirst]): pick a
  /// roster member and authorize them as a payer for the launch member, then
  /// refresh the candidates and auto-select the added payer.
  Future<void> _onLinkPayer() async {
    final s = _bloc.state;
    final roster = s is MemberDetailLoaded
        ? s.allMembers
        : const <MemberSummary>[];
    final exclude = <String>{
      widget.member.memberId,
      ..._payerCandidates.map((a) => a.memberId),
    };
    final candidates = roster
        .where((m) => !exclude.contains(m.memberId))
        .toList();
    final tokenBefore =
        s is MemberDetailLoaded ? s.refreshToken : -1;
    final linkedId = await StartLinkMemberDialog.show(
      context: context,
      direction: AuthorizeDirection.addPayer,
      anchorMemberId: widget.member.memberId,
      anchorName: widget.member.fullName,
      candidates: candidates,
    );
    if (linkedId == null || !mounted) return;
    await awaitMemberDetailSettle(_bloc, tokenBefore);
    if (!mounted) return;
    _refreshPayerCandidates(select: linkedId);
  }

  /// Rebuilds the payer candidate list from the reloaded LAUNCH member (the
  /// bloc's viewed member, whose `authorizedPayers` now carries the new payer)
  /// and auto-selects the added payer via [_onPayerSelected].
  void _refreshPayerCandidates({required String select}) {
    final s = _bloc.state;
    if (s is MemberDetailLoaded) {
      setState(() {
        _payerCandidates = s.member.authorizedPayers;
      });
    }
    _selectPayerById(select);
  }

  /// Selects the payer with [memberId] (a launch-member self-pay or a payer
  /// candidate) via the existing [_onPayerSelected], which resets the run's
  /// downstream selection to the launch member.
  void _selectPayerById(String memberId) {
    final p = _payerParticipantFor(memberId);
    if (p != null) _onPayerSelected(p);
  }

  StartMembershipParticipant? _payerParticipantFor(
    String memberId,
  ) {
    if (memberId == widget.member.memberId) {
      return StartMembershipParticipant(
        memberId: widget.member.memberId,
        name: widget.member.fullName,
        photoUrl: widget.member.photoUrl,
        isPayer: true,
      );
    }
    for (final a in _payerCandidates) {
      if (a.memberId == memberId) {
        return StartMembershipParticipant(
          memberId: a.memberId,
          name: a.fullName,
          photoUrl: a.photoUrl,
          isPayer: true,
        );
      }
    }
    return null;
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
    await awaitMemberDetailSettle(_bloc, tokenBefore);
    if (!mounted) return;
    await _loadPayerDetail();
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
      case StartMembershipsStep.signWaivers:
        return _waiversAllSigned;
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
    // Listen for the 422 waiver gate (waiverGate transitioning
    // from null → non-null on the bloc state). The start POST
    // fires from _onPay() and immediately sets _step = results
    // so the results step shows a spinner; if the bloc comes
    // back with a gate instead of a result, we redirect here.
    // buildWhen only triggers on results so the footer stays
    // in sync during the start POST — setState() in the listener
    // always rebuilds the widget tree regardless.
    return BlocConsumer<MemberDetailBloc,
        MemberDetailState>(
      listenWhen: (prev, curr) {
        if (curr is! MemberDetailLoaded) return false;
        if (prev is! MemberDetailLoaded) return false;
        return prev.waiverGate == null &&
            curr.waiverGate != null;
      },
      listener: (context, state) {
        if (state is! MemberDetailLoaded) return;
        final gate = state.waiverGate;
        if (gate == null) return;
        _routeToSignWaivers(gate);
      },
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
            showAddMemberGroup: widget.showAddMemberGroup,
            memberIndex: _memberIndex,
            hasWaiver: _waiverGate != null,
            payer: _payer,
            payerDetail: _payerDetail,
            payerCandidates: _payerCandidates,
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
            prorationBehavior: _prorationBehavior,
            paidWithCash: _paidWithCash,
            hasRecurring: _hasRecurring,
            hasOneTime: _hasOneTime,
            customCard: _customCard,
            payerCardOnFile: _payerDetail?.cardOnFile,
            memberNames: memberNamesOf(_configMembers),
            planNames: planNamesOf(_drafts),
            unsignedWaivers: _waiverGate?.unsigned,
            onWaiversSigned: () =>
                setState(() => _waiversAllSigned = true),
            onWaiverGate: _routeToSignWaivers,
            onPayerSelected: _onPayerSelected,
            onMemberToggle: _onMemberToggle,
            onLinkFirst: _onLinkFirst,
            onNewMember: _onNewMember,
            onNewPayer: _onNewPayer,
            onLinkPayer: _onLinkPayer,
            onPlanToggle: _onPlanToggle,
            onDraftChanged: _updateDraft,
            onPreviewLoaded: (p) =>
                setState(() => _preview = p),
            onProrationChanged: _onProrationChanged,
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
