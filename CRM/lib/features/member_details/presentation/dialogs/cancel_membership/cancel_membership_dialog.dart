import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_membership_checklist.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_membership_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_participant_banner.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_step_indicator.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_target.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant_step.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/billing_confirmation_dialog.dart';

/// Two-step cancellation flow:
///   1. Pick which covered person to cancel for. Linked
///      accounts with no recurring memberships to cancel are
///      greyed out. Skipped when the member has no linked
///      accounts.
///   2. Pick the recurring membership to cancel for that
///      person, then confirm via [BillingConfirmationDialog].
class CancelMembershipDialog extends StatefulWidget {
  final MemberDetailResponse member;

  /// The membership the carousel was showing when cancel was
  /// pressed — used to seed the default participant.
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
  late CancelMembershipStep _step;
  late StartMembershipParticipant _participant;
  String? _selectedItemId;

  bool get _hasLinked =>
      widget.member.linkedAccounts.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Default to the first participant that actually has a
    // cancellable recurring membership, so the banner and
    // checklist open on someone with something to cancel.
    final initial = widget.initialMembership;
    final defaultMemberId =
        initial != null && initial.members.isNotEmpty
            ? initial.members.keys.first
            : _firstEligibleMemberId() ??
                widget.member.memberId;
    _participant = _buildParticipant(defaultMemberId);
    _step = _hasLinked
        ? CancelMembershipStep.participant
        : CancelMembershipStep.memberships;
  }

  String? _firstEligibleMemberId() {
    for (final id in [
      widget.member.memberId,
      ...widget.member.linkedAccounts.map((a) => a.memberId),
    ]) {
      if (_targetsFor(id).isNotEmpty) return id;
    }
    return null;
  }

  StartMembershipParticipant _buildParticipant(String id) {
    if (id == widget.member.memberId) {
      return StartMembershipParticipant(
        memberId: widget.member.memberId,
        name: widget.member.fullName,
        photoUrl: widget.member.photoUrl,
        isPayer: true,
      );
    }
    final a = widget.member.linkedAccounts.firstWhere(
      (la) => la.memberId == id,
    );
    return StartMembershipParticipant(
      memberId: a.memberId,
      name: a.fullName,
      photoUrl: a.photoUrl,
      isPayer: false,
    );
  }

  List<CancelTarget> _targetsFor(String memberId) {
    final out = <CancelTarget>[];
    for (final m in widget.member.memberships) {
      if (!_isRecurring(m)) continue;
      final info = m.members[memberId];
      if (info == null) continue;
      out.add(CancelTarget(membership: m, member: info));
    }
    return out;
  }

  Map<String, String> get _disabledMemberIds {
    final map = <String, String>{};
    for (final id in [
      widget.member.memberId,
      ...widget.member.linkedAccounts.map((a) => a.memberId),
    ]) {
      if (_targetsFor(id).isEmpty) {
        map[id] = 'No recurring memberships to cancel';
      }
    }
    return map;
  }

  void _next() =>
      setState(() => _step = CancelMembershipStep.memberships);
  void _back() =>
      setState(() => _step = CancelMembershipStep.participant);

  @override
  Widget build(BuildContext context) {
    final targets = _targetsFor(_participant.memberId);
    final canConfirm = _selectedItemId != null;

    final primaryLabel =
        _step == CancelMembershipStep.participant
            ? 'Next'
            : 'Review cancellation';
    final primaryOnPressed = switch (_step) {
      CancelMembershipStep.participant =>
        _disabledMemberIds.containsKey(_participant.memberId)
            ? null
            : _next,
      CancelMembershipStep.memberships =>
        canConfirm ? _onConfirm : null,
    };
    final secondaryLabel = switch (_step) {
      CancelMembershipStep.participant => 'Cancel',
      CancelMembershipStep.memberships =>
        _hasLinked ? 'Back' : 'Cancel',
    };
    final secondaryOnPressed = switch (_step) {
      CancelMembershipStep.participant => () =>
          Navigator.of(context).pop(),
      CancelMembershipStep.memberships =>
        _hasLinked ? _back : () => Navigator.of(context).pop(),
    };

    return AppDialog(
      title: 'Cancel membership',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          if (_hasLinked) CancelStepIndicator(step: _step),
          if (_step == CancelMembershipStep.memberships)
            CancelParticipantBanner(participant: _participant),
          switch (_step) {
            CancelMembershipStep.participant =>
              StartMembershipParticipantStep(
                member: widget.member,
                selectedMemberId: _participant.memberId,
                onSelected: (p) => setState(() {
                  _participant = p;
                  _selectedItemId = null;
                }),
                disabledMemberIds: _disabledMemberIds,
                title: 'Who are you cancelling for?',
                subtitle: 'People without recurring '
                    'memberships are greyed out.',
              ),
            CancelMembershipStep.memberships =>
              CancelMembershipChecklist(
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
    final target = _targetsFor(_participant.memberId)
        .firstWhere((t) => t.member.itemId == itemId);

    final initial = _participant.name.isNotEmpty
        ? _participant.name[0].toUpperCase()
        : '?';
    final dateFmt = DateFormat('MMM d, yyyy');

    final confirmed = await BillingConfirmationDialog.show(
      context: context,
      title: 'Confirm cancellation',
      summary: 'Cancelling ${target.membership.planName} for '
          '${_participant.name}. Access ends after the '
          'current cycle.',
      effects: [
        BillingEffect(
          icon: Symbols.block_sharp,
          iconColor: DesignConstants.badRed,
          text: '${target.membership.planName} — access '
              'until '
              '${dateFmt.format(_accessUntil(target).toLocal())}.',
        ),
        const BillingEffect(
          icon: Symbols.payments_sharp,
          text: 'Recurring billing stops for this membership.',
        ),
      ],
      affected: [
        BillingAffectedPerson(
          fullName: _participant.name,
          initial: initial,
          photoUrl: _participant.photoUrl,
        ),
      ],
      confirmLabel: 'Cancel membership',
      confirmColor: DesignConstants.badRed,
    );
    if (!confirmed || !mounted) return;

    context.read<MemberDetailBloc>().add(
          CancelMembershipRequested(
            itemId: target.member.itemId,
            memberId: _participant.memberId,
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

  static DateTime _accessUntil(CancelTarget t) =>
      t.member.exitDate?.date ??
      t.membership.nextDueDate ??
      t.membership.startDate;
}
