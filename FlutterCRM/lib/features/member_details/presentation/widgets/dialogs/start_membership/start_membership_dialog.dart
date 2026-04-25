import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:uuid/uuid.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/start_membership/start_membership_discount_step.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/start_membership/start_membership_participant.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/start_membership/start_membership_participant_step.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/start_membership/start_membership_plan_step.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/start_membership/start_membership_review_step.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/billing_confirmation_dialog.dart';

enum _Step { participant, plan, discounts, review }

/// Multi-step flow for starting a new membership:
/// 0. (linked accounts only) Pick the participant.
/// 1. Pick a plan (and its active price).
/// 2. Optionally apply gym discounts.
/// 3. Review a live invoice preview and confirm.
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
    final bloc = context.read<MemberDetailBloc>();
    final repository = context.read<MemberRepository>();
    return showDialog<void>(
      context: context,
      builder: (_) => RepositoryProvider.value(
        value: repository,
        child: BlocProvider.value(
          value: bloc,
          child: StartMembershipDialog(member: member),
        ),
      ),
    );
  }

  @override
  State<StartMembershipDialog> createState() =>
      _StartMembershipDialogState();
}

class _StartMembershipDialogState
    extends State<StartMembershipDialog> {
  late _Step _step;
  late StartMembershipParticipant _participant;
  MembershipPlanResponse? _plan;
  final Set<String> _discountIds = {};
  bool _prorate = true;
  bool _paidWithCash = false;
  final String _idempotencyKey = const Uuid().v4();

  /// Cache of full member details keyed by `crmUserId`.
  /// Pre-seeded with the primary; linked-account entries
  /// are populated asynchronously in `initState` so the
  /// plan-tile rules (active/past memberships) can resolve
  /// for any selected participant — not just the primary.
  final Map<String, MemberDetailResponse> _participantData =
      {};

  bool get _hasLinked =>
      widget.member.linkedAccounts.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _participant = StartMembershipParticipant(
      crmUserId: widget.member.crmUserId,
      name: widget.member.fullName,
      photoUrl: widget.member.photoUrl,
      isPayer: true,
    );
    _step = _hasLinked ? _Step.participant : _Step.plan;
    _participantData[widget.member.crmUserId] =
        widget.member;
    _loadLinkedAccountData();
  }

  Future<void> _loadLinkedAccountData() async {
    final repo = context.read<MemberRepository>();
    for (final la in widget.member.linkedAccounts) {
      try {
        final detail = await repo.getMemberDetail(
          la.crmUserId,
        );
        if (!mounted) return;
        setState(() {
          _participantData[la.crmUserId] = detail;
        });
      } catch (_) {
        // Best-effort: missing data just means the
        // participant gets no inline warnings — selection
        // still works and the backend is the source of
        // truth.
      }
    }
  }

  /// Memberships the selected participant is actually
  /// enrolled in. The parent's detail response also lists
  /// plans they pay for on behalf of linked children, so
  /// filter down to rows whose `members` map includes the
  /// participant — otherwise the parent would inherit a
  /// child's active plan and get blocked from enrolling.
  List<MembershipInfo> get _currentMemberships {
    final data = _participantData[_participant.crmUserId];
    if (data == null) return const [];
    return data.memberships
        .where(
          (m) => m.members.containsKey(
            _participant.crmUserId,
          ),
        )
        .toList();
  }

  /// Maps `planId` → friendly "already on this plan" note
  /// for plans the selected participant already has an
  /// active recurring/trial membership on (one-time
  /// excluded — repeat one-time purchases are allowed).
  Map<String, String> get _disabledPlanReasons {
    final blocking = _currentMemberships.where(
      (m) =>
          m.planType != 'one_time' &&
          const {
            MembershipStatus.active,
            MembershipStatus.trial,
            MembershipStatus.frozen,
            MembershipStatus.overdue,
          }.contains(m.status),
    );
    return {
      for (final m in blocking)
        m.planId: 'Already on this plan',
    };
  }

  /// True when the selected participant already has an
  /// active one-time membership; surfaces as a yellow note
  /// on every one-time plan tile.
  bool get _participantHasActiveOneTime {
    return _currentMemberships.any(
      (m) =>
          m.planType == 'one_time' &&
          const {
            MembershipStatus.active,
            MembershipStatus.frozen,
            MembershipStatus.overdue,
          }.contains(m.status),
    );
  }

  /// Soft yellow inline notes per planId. Currently used
  /// for trial plans the selected participant has
  /// previously completed (status `cancelled` or `ended`).
  /// Selectable, but the staff member should know.
  Map<String, String> get _warningPlanReasons {
    final pastTrials = _currentMemberships.where(
      (m) =>
          m.planType == 'trial' &&
          const {
            MembershipStatus.cancelled,
            MembershipStatus.ended,
          }.contains(m.status),
    );
    return {
      for (final m in pastTrials)
        m.planId: 'Had this trial in the past',
    };
  }

  void _next() {
    setState(() {
      _step = switch (_step) {
        _Step.participant => _Step.plan,
        _Step.plan => _Step.discounts,
        _Step.discounts => _Step.review,
        _Step.review => _Step.review,
      };
    });
  }

  void _back() {
    setState(() {
      _step = switch (_step) {
        _Step.participant => _Step.participant,
        _Step.plan =>
          _hasLinked ? _Step.participant : _Step.plan,
        _Step.discounts => _Step.plan,
        _Step.review => _Step.discounts,
      };
    });
  }

  MemberMembershipsStartRequest? _buildRequest() {
    final plan = _plan;
    final priceId = plan?.activePrice?.priceId;
    if (plan == null || priceId == null) return null;
    final isRecurring =
        plan.planType == PlanType.recurring;
    return MemberMembershipsStartRequest(
      crmUserId: _participant.crmUserId,
      gymId: widget.member.gymId,
      planId: plan.planId,
      priceId: priceId,
      discountIds:
          _discountIds.isEmpty ? null : _discountIds.toList(),
      prorate: isRecurring ? _prorate : false,
      paidWithCash: _paidWithCash,
      idempotencyKey: _idempotencyKey,
    );
  }

  Future<void> _onConfirm() async {
    final req = _buildRequest();
    final plan = _plan;
    final price = plan?.activePrice;
    if (req == null || plan == null || price == null) return;

    final isRecurring =
        plan.planType == PlanType.recurring;
    final priceLabel = formatMinorUnits(
      price.price,
      currency: 'USD',
    );
    final effects = <BillingEffect>[
      BillingEffect(
        icon: Symbols.person_sharp,
        text: 'Membership for ${_participant.name}'
            '${_participant.isPayer ? '' : ' (linked account)'}.',
      ),
      BillingEffect(
        icon: Symbols.play_circle_sharp,
        text: 'Start ${plan.planName} · $priceLabel.',
      ),
      if (_paidWithCash)
        const BillingEffect(
          icon: Symbols.payments_sharp,
          text: 'Paid in cash — no card charge.',
        )
      else if (isRecurring)
        BillingEffect(
          icon: Symbols.credit_card_sharp,
          text: _prorate
              ? 'Card charged a prorated amount today.'
              : 'Card charged the full plan price today.',
        )
      else
        const BillingEffect(
          icon: Symbols.credit_card_sharp,
          text: 'Card charged once today — '
              'no recurring bill.',
        ),
      if (!_participant.isPayer)
        BillingEffect(
          icon: Symbols.account_balance_wallet_sharp,
          text:
              '${widget.member.fullName} is the billable '
              'account holder.',
        ),
      if (_discountIds.isNotEmpty)
        BillingEffect(
          icon: Symbols.local_offer_sharp,
          text:
              '${_discountIds.length} discount(s) applied.',
        ),
    ];

    final summary = isRecurring
        ? 'Starts ${plan.planName} and begins recurring '
            'billing for ${_participant.name}.'
        : 'Starts ${plan.planName} for ${_participant.name} '
            'as a one-time membership.';

    final confirmed =
        await BillingConfirmationDialog.show(
      context: context,
      title: 'Confirm new membership',
      summary: summary,
      effects: effects,
      affected: const [],
      confirmLabel: 'Start Membership',
      confirmColor: DesignConstants.primaryColor,
    );
    if (!confirmed || !mounted) return;

    context
        .read<MemberDetailBloc>()
        .add(StartMembershipRequested(req));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final disabledPlanReasons = _disabledPlanReasons;
    final warningPlanReasons = _warningPlanReasons;
    final hasActiveOneTime = _participantHasActiveOneTime;
    final selectedBlocked = _plan != null &&
        disabledPlanReasons.containsKey(_plan!.planId);
    final canAdvance = switch (_step) {
      _Step.participant => true,
      _Step.plan => _plan?.activePrice != null &&
          !selectedBlocked,
      _Step.discounts => true,
      _Step.review =>
        _buildRequest() != null && !selectedBlocked,
    };
    final primaryLabel = switch (_step) {
      _Step.participant => 'Next',
      _Step.plan => 'Next',
      _Step.discounts => 'Next',
      _Step.review => 'Review Start',
    };
    final primaryOnPressed = canAdvance
        ? (_step == _Step.review ? _onConfirm : _next)
        : null;
    final secondaryLabel =
        _step == _firstStep ? 'Cancel' : 'Back';
    final secondaryOnPressed = _step == _firstStep
        ? () => Navigator.of(context).pop()
        : _back;

    return AppDialog(
      title: 'Start Membership',
      body: _StepBody(
        step: _step,
        member: widget.member,
        participant: _participant,
        plan: _plan,
        discountIds: _discountIds,
        prorate: _prorate,
        paidWithCash: _paidWithCash,
        request: _buildRequest(),
        disabledPlanReasons: disabledPlanReasons,
        warningPlanReasons: warningPlanReasons,
        participantHasActiveOneTime: hasActiveOneTime,
        showParticipantStep: _hasLinked,
        onParticipantSelected: (p) =>
            setState(() => _participant = p),
        onPlanSelected: (p) => setState(() => _plan = p),
        onToggleDiscount: (id, v) => setState(() {
          if (v) {
            _discountIds.add(id);
          } else {
            _discountIds.remove(id);
          }
        }),
        onProrateChanged: (v) =>
            setState(() => _prorate = v),
        onPaidWithCashChanged: (v) =>
            setState(() => _paidWithCash = v),
      ),
      actions: AppDialogActions(
        primaryLabel: primaryLabel,
        primaryOnPressed: primaryOnPressed,
        secondaryLabel: secondaryLabel,
        secondaryOnPressed: secondaryOnPressed,
      ),
    );
  }

  _Step get _firstStep =>
      _hasLinked ? _Step.participant : _Step.plan;
}

class _StepBody extends StatelessWidget {
  final _Step step;
  final MemberDetailResponse member;
  final StartMembershipParticipant participant;
  final MembershipPlanResponse? plan;
  final Set<String> discountIds;
  final bool prorate;
  final bool paidWithCash;
  final MemberMembershipsStartRequest? request;
  final Map<String, String> disabledPlanReasons;
  final Map<String, String> warningPlanReasons;
  final bool participantHasActiveOneTime;
  final bool showParticipantStep;
  final ValueChanged<StartMembershipParticipant>
      onParticipantSelected;
  final ValueChanged<MembershipPlanResponse> onPlanSelected;
  final void Function(String id, bool selected)
      onToggleDiscount;
  final ValueChanged<bool> onProrateChanged;
  final ValueChanged<bool> onPaidWithCashChanged;

  const _StepBody({
    required this.step,
    required this.member,
    required this.participant,
    required this.plan,
    required this.discountIds,
    required this.prorate,
    required this.paidWithCash,
    required this.request,
    required this.disabledPlanReasons,
    required this.warningPlanReasons,
    required this.participantHasActiveOneTime,
    required this.showParticipantStep,
    required this.onParticipantSelected,
    required this.onPlanSelected,
    required this.onToggleDiscount,
    required this.onProrateChanged,
    required this.onPaidWithCashChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        _StepIndicator(
          step: step,
          showParticipantStep: showParticipantStep,
        ),
        if (step != _Step.participant)
          _ParticipantBanner(participant: participant),
        switch (step) {
          _Step.participant =>
            StartMembershipParticipantStep(
              member: member,
              selectedCrmUserId: participant.crmUserId,
              onSelected: onParticipantSelected,
            ),
          _Step.plan => StartMembershipPlanStep(
              gymId: member.gymId,
              selected: plan,
              onSelected: onPlanSelected,
              disabledPlanReasons: disabledPlanReasons,
              warningPlanReasons: warningPlanReasons,
              participantHasActiveOneTime:
                  participantHasActiveOneTime,
            ),
          _Step.discounts => StartMembershipDiscountStep(
              gymId: member.gymId,
              selected: discountIds,
              onToggle: onToggleDiscount,
            ),
          _Step.review => StartMembershipReviewStep(
              request: request,
              planType: plan?.planType ?? PlanType.unknown,
              prorate: prorate,
              paidWithCash: paidWithCash,
              onProrateChanged: onProrateChanged,
              onPaidWithCashChanged: onPaidWithCashChanged,
            ),
        },
      ],
    );
  }
}

class _ParticipantBanner extends StatelessWidget {
  final StartMembershipParticipant participant;

  const _ParticipantBanner({required this.participant});

  @override
  Widget build(BuildContext context) {
    final initial = participant.name.isNotEmpty
        ? participant.name[0].toUpperCase()
        : '?';
    return Container(
      padding: const EdgeInsets.all(
        DesignConstants.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor.withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: DesignConstants.card,
            backgroundImage: participant.photoUrl != null
                ? NetworkImage(participant.photoUrl!)
                : null,
            child: participant.photoUrl == null
                ? Text(
                    initial,
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text,
                    ),
                  )
                : null,
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
                children: [
                  const TextSpan(text: 'Membership for '),
                  TextSpan(
                    text: participant.name,
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: participant.isPayer
                        ? ''
                        : ' (linked account)',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final _Step step;
  final bool showParticipantStep;

  const _StepIndicator({
    required this.step,
    required this.showParticipantStep,
  });

  @override
  Widget build(BuildContext context) {
    final visibleSteps = <_Step>[
      if (showParticipantStep) _Step.participant,
      _Step.plan,
      _Step.discounts,
      _Step.review,
    ];
    final labels = visibleSteps
        .map(
          (s) => switch (s) {
            _Step.participant => 'Person',
            _Step.plan => 'Plan',
            _Step.discounts => 'Discounts',
            _Step.review => 'Review',
          },
        )
        .toList();
    final index = visibleSteps.indexOf(step);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(labels.length, (i) {
        final active = i == index;
        final done = i < index;
        final color = active
            ? DesignConstants.primaryColor
            : done
                ? DesignConstants.goodGreen
                : DesignConstants.text3rd;
        return Expanded(
          child: Column(
            spacing: DesignConstants.spacingTiny,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                labels[i],
                style: DesignConstants.pSmall.copyWith(
                  color: color,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
