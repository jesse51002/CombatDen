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
import 'package:crm/features/member_details/data/models/member_memberships_start_item.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/member_summary.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/membership_draft.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_link_member_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_step_body.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_plan_rules.dart'
    as rules;
import 'package:crm/features/member_details/presentation/dialogs/update_card_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// The Start Memberships wizard — one request per run:
/// 1. who pays (only the top-level paying account),
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
  MemberMembershipsStartRequest? _previewRequest;
  MemberMembershipsStartPreview? _preview;

  @override
  void initState() {
    super.initState();
    _bloc = context.read<MemberDetailBloc>();
    _bloc.add(const StartMembershipsCleared());
    _plansFuture =
        _repository.listMembershipPlans(widget.member.gymId);
    _initPayer();
  }

  @override
  void dispose() {
    // Leave no stale breakdown behind for the next run
    // (the bloc outlives this dialog; it may already be
    // closed when the whole screen tears down).
    try {
      _bloc.add(const StartMembershipsCleared());
    } catch (_) {}
    super.dispose();
  }

  /// The payer is the top-level paying account: the viewed
  /// member when they are not linked to anyone, otherwise
  /// the account they are linked to.
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

  // ----- Derived -----

  /// Selected members in stable family order (payer first).
  List<StartMembershipParticipant> get _configMembers {
    final detail = _payerDetail;
    final all = <StartMembershipParticipant>[
      _payer,
      if (detail != null)
        ...detail.linkedAccounts.map(
          (a) => StartMembershipParticipant(
            memberId: a.memberId,
            name: a.fullName,
            photoUrl: a.photoUrl,
            isPayer: false,
          ),
        ),
    ];
    return all
        .where(
          (p) =>
              _selectedMemberIds.contains(p.memberId),
        )
        .toList();
  }

  StartMembershipParticipant? get _currentMember {
    final members = _configMembers;
    if (members.isEmpty) return null;
    final i = _memberIndex < members.length
        ? _memberIndex
        : members.length - 1;
    return members[i];
  }

  List<MembershipDraft> get _currentDrafts =>
      _drafts[_currentMember?.memberId] ?? const [];

  Map<String, String> get _disabledPlanReasons {
    final member = _currentMember;
    final detail = _memberDetails[member?.memberId];
    if (member == null || detail == null) return const {};
    return rules.disabledPlanReasons(
      rules.membershipsForParticipant(
        detail.memberships,
        member.memberId,
      ),
    );
  }

  /// The current member's existing non-terminal
  /// memberships — the Plans step's "Already has" block.
  /// Same best-effort detail fetch as the plan rules:
  /// empty when the fetch failed.
  List<MembershipInfo> get _existingMemberships {
    final member = _currentMember;
    final detail = _memberDetails[member?.memberId];
    if (member == null || detail == null) return const [];
    return rules.currentMembershipsForParticipant(
      detail.memberships,
      member.memberId,
    );
  }

  bool get _hasRecurring => _configMembers.any(
        (m) => (_drafts[m.memberId] ?? const [])
            .any(
              (d) =>
                  d.plan.planType == PlanType.recurring,
            ),
      );

  Map<String, String> get _memberNames => {
        for (final m in _configMembers)
          m.memberId: m.name,
      };

  Map<String, String> get _planNames => {
        for (final list in _drafts.values)
          for (final d in list)
            d.plan.planId: d.plan.planName,
      };

  MemberMembershipsStartRequest? _buildRequest(
    String idempotencyKey,
  ) {
    final items = <MemberMembershipsStartItem>[];
    for (final m in _configMembers) {
      for (final d
          in _drafts[m.memberId] ?? const <MembershipDraft>[]) {
        final item = d.toItem(m.memberId);
        if (item != null) items.add(item);
      }
    }
    if (items.isEmpty) return null;
    return MemberMembershipsStartRequest(
      payerMemberId: _payer.memberId,
      gymId: widget.member.gymId,
      idempotencyKey: idempotencyKey,
      prorate: _prorate,
      paidWithCash: _paidWithCash,
      memberships: items,
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
          if (_memberIndex + 1 < _configMembers.length) {
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
          if (_memberIndex == 0) {
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
    final req = _buildRequest(const Uuid().v4());
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
    final items = <MemberMembershipsStartItem>[];
    for (final f in result.failed) {
      for (final d
          in _drafts[f.memberId] ?? const <MembershipDraft>[]) {
        if (d.plan.planId != f.planId) continue;
        final item = d.toItem(f.memberId);
        if (item != null) items.add(item);
      }
    }
    if (items.isEmpty) return;
    _bloc.add(StartMembershipsRequested(
      MemberMembershipsStartRequest(
        payerMemberId: _payer.memberId,
        gymId: widget.member.gymId,
        idempotencyKey: const Uuid().v4(),
        prorate: _prorate,
        paidWithCash: _paidWithCash,
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

  // ----- Selection mutations -----

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
      final list = List<MembershipDraft>.from(
        _drafts[memberId] ?? const [],
      );
      final i = list.indexWhere(
        (d) => d.plan.planId == plan.planId,
      );
      if (i >= 0) {
        list.removeAt(i);
      } else {
        list.add(MembershipDraft(plan: plan));
      }
      _drafts[memberId] = list;
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
    // The update-card flow acts on the bloc's VIEWED
    // member, so it only applies when the payer launched
    // the wizard from their own page (linked accounts
    // can't hold a card anyway).
    if (widget.member.memberId != _payer.memberId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Update the card from ${_payer.name}’s '
            'page.',
          ),
        ),
      );
      return;
    }
    final s = _bloc.state;
    final tokenBefore =
        s is MemberDetailLoaded ? s.refreshToken : -1;
    await UpdateCardDialog.show(
      context: context,
      memberName: _payer.name,
      card: _payerDetail?.cardOnFile,
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
      case StartMembershipsStep.review:
        return true;
      case StartMembershipsStep.preview:
        return _previewRequest != null;
      case StartMembershipsStep.payment:
        return _paidWithCash ||
            _payerDetail?.cardOnFile != null;
      case StartMembershipsStep.results:
        return !_isStarting;
    }
  }

  bool get _isStarting {
    final s = _bloc.state;
    return s is MemberDetailLoaded &&
        s.isStartingMemberships;
  }

  String get _primaryLabel {
    switch (_step) {
      case StartMembershipsStep.payer:
      case StartMembershipsStep.members:
      case StartMembershipsStep.plans:
        return 'Next';
      case StartMembershipsStep.discounts:
        return _memberIndex + 1 < _configMembers.length
            ? 'Next member'
            : 'Review';
      case StartMembershipsStep.review:
        return 'Preview charges';
      case StartMembershipsStep.preview:
        return 'Continue to payment';
      case StartMembershipsStep.payment:
        return 'Pay';
      case StartMembershipsStep.results:
        return 'Done';
    }
  }

  void _onPrimary() {
    switch (_step) {
      case StartMembershipsStep.payment:
        _onPay();
      case StartMembershipsStep.results:
        Navigator.of(context).pop();
      default:
        _next();
    }
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
        final atFirst =
            _step == StartMembershipsStep.payer;
        final atResults =
            _step == StartMembershipsStep.results;
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
            disabledPlanReasons: _disabledPlanReasons,
            existingMemberships: _existingMemberships,
            plansFuture: _plansFuture,
            discountsFuture: _discountsFuture,
            previewRequest: _previewRequest,
            preview: _preview,
            prorate: _prorate,
            paidWithCash: _paidWithCash,
            hasRecurring: _hasRecurring,
            payerCardOnFile: _payerDetail?.cardOnFile,
            memberNames: _memberNames,
            planNames: _planNames,
            onPayerSelected: (p) =>
                setState(() => _payer = p),
            onMemberToggle: _onMemberToggle,
            onLinkFirst: _onLinkFirst,
            onPlanToggle: _onPlanToggle,
            onPlanCountChanged: (planId, count) =>
                _updateDraft(
              planId,
              (d) => d.copyWith(count: count),
            ),
            onPresetToggle: (planId, discountId) =>
                _updateDraft(planId, (d) {
              final ids = Set<String>.from(d.discountIds);
              if (!ids.remove(discountId)) {
                ids.add(discountId);
              }
              return d.copyWith(discountIds: ids);
            }),
            onCustomAdded: (planId, value) =>
                _updateDraft(
              planId,
              (d) => d.copyWith(
                customDiscounts: [
                  ...d.customDiscounts,
                  value,
                ],
              ),
            ),
            onCustomRemoved: (planId, index) =>
                _updateDraft(planId, (d) {
              final customs = List.of(d.customDiscounts)
                ..removeAt(index);
              return d.copyWith(
                customDiscounts: customs,
              );
            }),
            onPreviewLoaded: (p) =>
                setState(() => _preview = p),
            onProrateChanged: _onProrateChanged,
            onPaidWithCashChanged: (v) =>
                setState(() => _paidWithCash = v),
            onAddNewCard: _onAddNewCard,
            onRetryFailed: _onRetryFailed,
            onViewMember: _onViewMember,
            onBackToPayment: () => setState(
              () =>
                  _step = StartMembershipsStep.payment,
            ),
          ),
          actions: AppDialogActions(
            primaryLabel: _primaryLabel,
            isLoading: atResults && _isStarting,
            primaryOnPressed:
                _canAdvance ? _onPrimary : null,
            secondaryLabel: atResults
                ? null
                : (atFirst ? 'Cancel' : 'Back'),
            secondaryOnPressed: atFirst
                ? () => Navigator.of(context).pop()
                : _back,
          ),
        );
      },
    );
  }
}
