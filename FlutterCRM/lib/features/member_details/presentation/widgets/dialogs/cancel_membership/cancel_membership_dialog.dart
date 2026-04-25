import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_member_info.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/start_membership/start_membership_participant.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/start_membership/start_membership_participant_step.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/billing_confirmation_dialog.dart';

enum _Step { participant, memberships }

/// Two-step cancellation flow:
///   1. Pick which covered person to cancel for. Linked
///      accounts with no recurring memberships to cancel
///      are greyed out.
///   2. Check off the recurring memberships to cancel for
///      that person.
class CancelMembershipDialog extends StatefulWidget {
  final MemberDetailResponse member;
  final MembershipInfo? initialMembership;

  const CancelMembershipDialog({
    super.key,
    required this.member,
    this.initialMembership,
  });

  static Future<void> show({
    required BuildContext context,
    required MemberDetailResponse member,
    MembershipInfo? initialMembership,
  }) {
    final bloc = context.read<MemberDetailBloc>();
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: CancelMembershipDialog(
          member: member,
          initialMembership: initialMembership,
        ),
      ),
    );
  }

  @override
  State<CancelMembershipDialog> createState() =>
      _CancelMembershipDialogState();
}

class _CancelMembershipDialogState
    extends State<CancelMembershipDialog> {
  late _Step _step;
  late StartMembershipParticipant _participant;
  String? _selectedItemId;

  bool get _hasLinked =>
      widget.member.linkedAccounts.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Default to the first participant that actually has a
    // cancellable recurring membership, falling back to the
    // primary member. This keeps the banner honest when the
    // primary has nothing to cancel but a linked account
    // does.
    final initial = widget.initialMembership;
    final defaultCrmUserId =
        initial != null && initial.members.isNotEmpty
            ? initial.members.keys.first
            : _firstEligibleCrmUserId() ??
                widget.member.crmUserId;
    _participant = _buildParticipant(defaultCrmUserId);
    _step = _hasLinked ? _Step.participant : _Step.memberships;
  }

  String? _firstEligibleCrmUserId() {
    for (final id in [
      widget.member.crmUserId,
      ...widget.member.linkedAccounts.map((a) => a.crmUserId),
    ]) {
      if (_targetsFor(id).isNotEmpty) return id;
    }
    return null;
  }

  StartMembershipParticipant _buildParticipant(String id) {
    if (id == widget.member.crmUserId) {
      return StartMembershipParticipant(
        crmUserId: widget.member.crmUserId,
        name: widget.member.fullName,
        photoUrl: widget.member.photoUrl,
        isPayer: true,
      );
    }
    final a = widget.member.linkedAccounts.firstWhere(
      (la) => la.crmUserId == id,
    );
    return StartMembershipParticipant(
      crmUserId: a.crmUserId,
      name: a.fullName,
      photoUrl: a.photoUrl,
      isPayer: false,
    );
  }

  List<_CancelTarget> _targetsFor(String crmUserId) {
    final out = <_CancelTarget>[];
    for (final m in widget.member.memberships) {
      if (!_isRecurring(m)) continue;
      final info = m.members[crmUserId];
      if (info == null) continue;
      out.add(_CancelTarget(membership: m, member: info));
    }
    return out;
  }

  Map<String, String> get _disabledCrmUserIds {
    final map = <String, String>{};
    for (final id in [
      widget.member.crmUserId,
      ...widget.member.linkedAccounts.map((a) => a.crmUserId),
    ]) {
      if (_targetsFor(id).isEmpty) {
        map[id] = 'No recurring memberships to cancel';
      }
    }
    return map;
  }

  void _next() {
    setState(() => _step = _Step.memberships);
  }

  void _back() {
    setState(() => _step = _Step.participant);
  }

  @override
  Widget build(BuildContext context) {
    final targets = _targetsFor(_participant.crmUserId);
    final canConfirm = _selectedItemId != null;

    final primaryLabel = _step == _Step.participant
        ? 'Next'
        : 'Review Cancellation';
    final primaryOnPressed = switch (_step) {
      _Step.participant =>
        _disabledCrmUserIds.containsKey(
          _participant.crmUserId,
        )
            ? null
            : _next,
      _Step.memberships => canConfirm ? _onConfirm : null,
    };
    final secondaryLabel = switch (_step) {
      _Step.participant => 'Cancel',
      _Step.memberships => _hasLinked ? 'Back' : 'Cancel',
    };
    final secondaryOnPressed = switch (_step) {
      _Step.participant => () =>
          Navigator.of(context).pop(),
      _Step.memberships => _hasLinked
          ? _back
          : () => Navigator.of(context).pop(),
    };

    return AppDialog(
      title: 'Cancel Membership',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          if (_hasLinked)
            _StepIndicator(step: _step),
          if (_step == _Step.memberships)
            _ParticipantBanner(participant: _participant),
          switch (_step) {
            _Step.participant =>
              StartMembershipParticipantStep(
                member: widget.member,
                selectedCrmUserId: _participant.crmUserId,
                onSelected: (p) => setState(() {
                  _participant = p;
                  _selectedItemId = null;
                }),
                disabledCrmUserIds: _disabledCrmUserIds,
                title: 'Who are you cancelling for?',
                subtitle:
                    'People without recurring memberships '
                    'are greyed out.',
              ),
            _Step.memberships => _MembershipChecklist(
                targets: targets,
                selectedItemId: _selectedItemId,
                onSelect: (itemId) => setState(
                  () => _selectedItemId = itemId,
                ),
              ),
          },
        ],
      ),
      actions: AppDialogActions(
        primaryLabel: primaryLabel,
        primaryColor: DesignConstants.badRed,
        primaryOnPressed: primaryOnPressed,
        secondaryLabel: secondaryLabel,
        secondaryOnPressed: secondaryOnPressed,
      ),
    );
  }

  Future<void> _onConfirm() async {
    final itemId = _selectedItemId;
    if (itemId == null) return;
    final target = _targetsFor(_participant.crmUserId)
        .firstWhere(
      (t) => t.member.itemId == itemId,
    );

    final initial = _participant.name.isNotEmpty
        ? _participant.name[0].toUpperCase()
        : '?';
    final affected = BillingAffectedPerson(
      fullName: _participant.name,
      initial: initial,
      photoUrl: _participant.photoUrl,
    );
    final dateFmt = DateFormat('MMM d, yyyy');

    final confirmed =
        await BillingConfirmationDialog.show(
      context: context,
      title: 'Confirm cancellation',
      summary: 'Cancelling ${target.membership.planName} '
          'for ${_participant.name}. Access ends after '
          'the current cycle.',
      effects: [
        BillingEffect(
          icon: Symbols.block_sharp,
          iconColor: DesignConstants.badRed,
          text: '${target.membership.planName} — access '
              'until '
              '${dateFmt.format(
            _accessUntil(target).toLocal(),
          )}.',
        ),
        const BillingEffect(
          icon: Symbols.payments_sharp,
          text: 'Recurring billing stops for this '
              'membership.',
        ),
      ],
      affected: [affected],
      confirmLabel: 'Cancel Membership',
      confirmColor: DesignConstants.badRed,
    );
    if (!confirmed || !mounted) return;

    context.read<MemberDetailBloc>().add(
          CancelMembershipRequested(
            itemId: target.member.itemId,
            crmUserId: _participant.crmUserId,
          ),
        );
    Navigator.of(context).pop();
  }

  static bool _isRecurring(MembershipInfo m) =>
      m.planType == 'recurring' &&
      const {
        MembershipStatus.active,
        MembershipStatus.trial,
        MembershipStatus.frozen,
        MembershipStatus.overdue,
      }.contains(m.status);

  static DateTime _accessUntil(_CancelTarget t) =>
      t.member.exitDate?.date ??
      t.membership.nextDueDate ??
      t.membership.startDate;
}

class _CancelTarget {
  final MembershipInfo membership;
  final MembershipMemberInfo member;

  const _CancelTarget({
    required this.membership,
    required this.member,
  });
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
        color: DesignConstants.badRed.withValues(
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
                  const TextSpan(text: 'Cancelling for '),
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

  const _StepIndicator({required this.step});

  @override
  Widget build(BuildContext context) {
    const labels = ['Person', 'Memberships'];
    final index = _Step.values.indexOf(step);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(labels.length, (i) {
        final active = i == index;
        final done = i < index;
        final color = active
            ? DesignConstants.badRed
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

class _MembershipChecklist extends StatelessWidget {
  final List<_CancelTarget> targets;
  final String? selectedItemId;
  final ValueChanged<String> onSelect;

  const _MembershipChecklist({
    required this.targets,
    required this.selectedItemId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (targets.isEmpty) {
      return Text(
        'No recurring memberships to cancel for this '
        'person.',
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.text2nd,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          'Select a membership to cancel',
          style: DesignConstants.h3,
        ),
        Text(
          'Cancelling ends access after the current '
          'cycle. Recurring billing stops on the next '
          'billing date.',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingSmall,
          children: targets
              .map(
                (t) => _MembershipRow(
                  target: t,
                  selected: selectedItemId ==
                      t.member.itemId,
                  onTap: () => onSelect(t.member.itemId),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _MembershipRow extends StatelessWidget {
  final _CancelTarget target;
  final bool selected;
  final VoidCallback onTap;

  const _MembershipRow({
    required this.target,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final exit = target.member.exitDate;
    final alreadyCancelling =
        exit?.kind == MembershipExitKind.cancelling;
    final dateFmt = DateFormat('MMM d, yyyy');
    final String subtitle;
    final Color subtitleColor;
    if (alreadyCancelling) {
      subtitle = 'Already cancelling '
          '${dateFmt.format(exit!.date.toLocal())}';
      subtitleColor = DesignConstants.okYellow;
    } else if (exit != null) {
      // Plan is ending naturally — still cancellable
      // before the end date. Show the end date but keep
      // the row selectable.
      subtitle = 'Ends '
          '${dateFmt.format(exit.date.toLocal())}';
      subtitleColor = DesignConstants.text2nd;
    } else {
      subtitle = 'Access until '
          '${dateFmt.format(
        (target.membership.nextDueDate ??
                target.membership.startDate)
            .toLocal(),
      )}';
      subtitleColor = DesignConstants.text2nd;
    }
    return InkWell(
      onTap: alreadyCancelling ? null : onTap,
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusSmall,
      ),
      child: Container(
        padding: const EdgeInsets.all(
          DesignConstants.spacingMedium,
        ),
        decoration: BoxDecoration(
          color: selected
              ? DesignConstants.badRed.withValues(
                  alpha: 0.12,
                )
              : DesignConstants.backgroundColor,
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
          border: Border.all(
            color: selected
                ? DesignConstants.badRed
                : DesignConstants.divider,
          ),
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              selected
                  ? Symbols.radio_button_checked_sharp
                  : Symbols.radio_button_unchecked_sharp,
              weight: DesignConstants.iconWeight,
              color: selected
                  ? DesignConstants.badRed
                  : DesignConstants.text2nd,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingTiny,
                children: [
                  Text(
                    target.membership.planName,
                    style: DesignConstants.h3,
                  ),
                  Text(
                    subtitle,
                    style: DesignConstants.pSmall.copyWith(
                      color: subtitleColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
