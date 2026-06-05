import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_plan_rules.dart'
    as rules;
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_step_body.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// Multi-step flow for starting a new membership:
/// 0. (linked accounts only) pick the participant,
/// 1. pick a plan (its active price drives `price_id`),
/// 2. review a live charge preview + toggle proration /
///    cash, then confirm.
///
/// Memberships are created discount-free; discounts are
/// applied afterward from the member's Manage Discounts
/// dialog. Dispatches [StartMembershipRequested] with a
/// fully populated [MemberMembershipsStartRequest].
class StartMembershipDialog extends StatefulWidget {
  final MemberDetailResponse member;

  const StartMembershipDialog({
    super.key,
    required this.member,
  });

  static Future<void> show({
    required BuildContext context,
    required MemberDetailResponse member,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: StartMembershipDialog(member: member),
      ),
    );
  }

  @override
  State<StartMembershipDialog> createState() =>
      _StartMembershipDialogState();
}

class _StartMembershipDialogState
    extends State<StartMembershipDialog> {
  final MemberRepository _repository =
      MemberRepository(apiClient: ApiClient());

  late StartMembershipStep _step;
  late StartMembershipParticipant _participant;
  MembershipPlanResponse? _plan;
  bool _prorate = true;
  bool _paidWithCash = false;
  final String _idempotencyKey = const Uuid().v4();

  /// Full member details keyed by `member_id` so plan-tile
  /// rules resolve for any selected participant. Seeded
  /// with the primary; linked accounts load best-effort.
  final Map<String, MemberDetailResponse> _participantData =
      {};

  bool get _hasLinked =>
      widget.member.linkedAccounts.isNotEmpty;

  StartMembershipStep get _firstStep => _hasLinked
      ? StartMembershipStep.participant
      : StartMembershipStep.plan;

  @override
  void initState() {
    super.initState();
    _participant = StartMembershipParticipant(
      memberId: widget.member.memberId,
      name: widget.member.fullName,
      photoUrl: widget.member.photoUrl,
      isPayer: true,
    );
    _step = _firstStep;
    _participantData[widget.member.memberId] =
        widget.member;
    _loadLinkedAccountData();
  }

  Future<void> _loadLinkedAccountData() async {
    for (final la in widget.member.linkedAccounts) {
      try {
        final detail =
            await _repository.getMemberDetail(la.memberId);
        if (!mounted) return;
        setState(
          () => _participantData[la.memberId] = detail,
        );
      } catch (_) {
        // Best-effort: missing data just means no inline
        // plan warnings for that participant — the backend
        // is the source of truth and still rejects dupes.
      }
    }
  }

  List<MembershipInfo> get _participantMemberships {
    final data = _participantData[_participant.memberId];
    if (data == null) return const [];
    return rules.membershipsForParticipant(
      data.memberships,
      _participant.memberId,
    );
  }

  MemberMembershipsStartRequest? _buildRequest() {
    final plan = _plan;
    final priceId = plan?.activePrice?.priceId;
    if (plan == null || priceId == null) return null;
    final isRecurring =
        plan.planType == PlanType.recurring;
    return MemberMembershipsStartRequest(
      memberId: _participant.memberId,
      gymId: widget.member.gymId,
      planId: plan.planId,
      priceId: priceId,
      prorate: isRecurring ? _prorate : false,
      paidWithCash: _paidWithCash,
      idempotencyKey: _idempotencyKey,
    );
  }

  void _next() {
    setState(() {
      _step = switch (_step) {
        StartMembershipStep.participant =>
          StartMembershipStep.plan,
        StartMembershipStep.plan =>
          StartMembershipStep.review,
        StartMembershipStep.review =>
          StartMembershipStep.review,
      };
    });
  }

  void _back() {
    setState(() {
      _step = switch (_step) {
        StartMembershipStep.participant =>
          StartMembershipStep.participant,
        StartMembershipStep.plan => _firstStep,
        StartMembershipStep.review =>
          StartMembershipStep.plan,
      };
    });
  }

  void _onConfirm() {
    final req = _buildRequest();
    if (req == null) return;
    context
        .read<MemberDetailBloc>()
        .add(StartMembershipRequested(req));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final current = _participantMemberships;
    final disabledReasons =
        rules.disabledPlanReasons(current);
    final warningReasons =
        rules.warningPlanReasons(current);
    final hasActiveOneTime =
        rules.participantHasActiveOneTime(current);
    final selectedBlocked = _plan != null &&
        disabledReasons.containsKey(_plan!.planId);

    final canAdvance = switch (_step) {
      StartMembershipStep.participant => true,
      StartMembershipStep.plan =>
        _plan?.activePrice != null && !selectedBlocked,
      StartMembershipStep.review =>
        _buildRequest() != null && !selectedBlocked,
    };
    final isReview = _step == StartMembershipStep.review;
    final atFirstStep = _step == _firstStep;

    return AppDialog(
      title: 'Start a membership',
      body: StartMembershipStepBody(
        step: _step,
        member: widget.member,
        repository: _repository,
        participant: _participant,
        plan: _plan,
        prorate: _prorate,
        paidWithCash: _paidWithCash,
        request: _buildRequest(),
        disabledPlanReasons: disabledReasons,
        warningPlanReasons: warningReasons,
        participantHasActiveOneTime: hasActiveOneTime,
        showParticipantStep: _hasLinked,
        onParticipantSelected: (p) =>
            setState(() => _participant = p),
        onPlanSelected: (p) => setState(() => _plan = p),
        onProrateChanged: (v) =>
            setState(() => _prorate = v),
        onPaidWithCashChanged: (v) =>
            setState(() => _paidWithCash = v),
      ),
      actions: AppDialogActions(
        primaryLabel: isReview ? 'Start membership' : 'Next',
        primaryOnPressed: canAdvance
            ? (isReview ? _onConfirm : _next)
            : null,
        secondaryLabel: atFirstStep ? 'Cancel' : 'Back',
        secondaryOnPressed: atFirstStep
            ? () => Navigator.of(context).pop()
            : _back,
      ),
    );
  }
}
