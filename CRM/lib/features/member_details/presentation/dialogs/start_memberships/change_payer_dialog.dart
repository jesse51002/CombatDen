import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/linked_account.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_option_row.dart';
import 'package:crm/features/membership_flow/config/membership_flow_scale.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/config/staff_flow_copy.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// Who pays for this run — a separate task with its own commit, so a dialog.
///
/// It is the `who` step's two adders pointed the OTHER way, which is precisely
/// why they no longer sit side by side on one screen: the old wizard offered
/// "add a payer" and "add a payee" as two identical-looking pairs on adjacent
/// steps, and staff picked the wrong one. Here the payee adders live on the
/// roster and the payer adders live behind this one named button.
///
/// It pops the chosen member id, or null when nothing changed. The CALLER
/// applies it — and applying it rebuilds the run, which the button that opens
/// this dialog says before it is pressed.
class ChangePayerDialog extends StatefulWidget {
  /// The member whose page opened the run. They are always a valid payer
  /// (self-pay), and every candidate below is one of THEIR authorized payers.
  final MemberDetailResponse launchMember;

  final String currentPayerId;
  final List<LinkedAccount> candidates;

  /// Create a new member and authorize them AS a payer. Resolves to their id.
  final Future<String?> Function() onCreatePayer;

  /// Pick an existing member and authorize them AS a payer.
  final Future<String?> Function() onLinkPayer;

  const ChangePayerDialog({
    super.key,
    required this.launchMember,
    required this.currentPayerId,
    required this.candidates,
    required this.onCreatePayer,
    required this.onLinkPayer,
  });

  static Future<String?> show({
    required BuildContext context,
    required MemberDetailResponse launchMember,
    required String currentPayerId,
    required List<LinkedAccount> candidates,
    required Future<String?> Function() onCreatePayer,
    required Future<String?> Function() onLinkPayer,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => ChangePayerDialog(
        launchMember: launchMember,
        currentPayerId: currentPayerId,
        candidates: candidates,
        onCreatePayer: onCreatePayer,
        onLinkPayer: onLinkPayer,
      ),
    );
  }

  @override
  State<ChangePayerDialog> createState() => _ChangePayerDialogState();
}

class _ChangePayerDialogState extends State<ChangePayerDialog> {
  late String _selected = widget.currentPayerId;

  /// A just-authorized payer is auto-selected: staff went to the trouble of
  /// adding them, and making them hunt for the row they just created is the
  /// kind of small insult that teaches people to distrust a flow.
  Future<void> _add(Future<String?> Function() authorize) async {
    final added = await authorize();
    if (added == null || !mounted) return;
    setState(() => _selected = added);
  }

  @override
  Widget build(BuildContext context) {
    return MembershipFlowTheme(
      scale: const MembershipFlowScale.admin(),
      copy: const StaffFlowCopy(),
      child: AppDialog(
        title: _kTitle,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingLarge,
          children: [
            Text(
              _kIntro,
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
            _PayerOptions(
              launchMember: widget.launchMember,
              candidates: widget.candidates,
              selected: _selected,
              onSelect: (id) => setState(() => _selected = id),
            ),
            const Hairline(),
            WizardOptionRow(
              icon: Symbols.person_add_sharp,
              title: _kCreateTitle,
              meta: _kCreateBody,
              opensMore: true,
              onTap: () => _add(widget.onCreatePayer),
            ),
            WizardOptionRow(
              icon: Symbols.search_sharp,
              title: _kLinkTitle,
              meta: _kLinkBody,
              opensMore: true,
              onTap: () => _add(widget.onLinkPayer),
            ),
          ],
        ),
        actions: AppDialogActions(
          primaryLabel: _kConfirm,
          primaryOnPressed: _selected == widget.currentPayerId
              ? null
              : () => Navigator.of(context).pop(_selected),
          secondaryLabel: _kCancel,
          secondaryOnPressed: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

/// The launch member (self-pay) and every payer authorized for them.
class _PayerOptions extends StatelessWidget {
  final MemberDetailResponse launchMember;
  final List<LinkedAccount> candidates;
  final String selected;
  final ValueChanged<String> onSelect;

  const _PayerOptions({
    required this.launchMember,
    required this.candidates,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        WizardOptionRow(
          icon: Symbols.person_sharp,
          title: launchMember.fullName,
          meta: _kSelfPay,
          selected: selected == launchMember.memberId,
          onTap: () => onSelect(launchMember.memberId),
        ),
        for (final account in candidates)
          WizardOptionRow(
            icon: Symbols.account_balance_wallet_sharp,
            title: account.fullName,
            meta: _kAuthorized,
            selected: selected == account.memberId,
            onTap: () => onSelect(account.memberId),
          ),
      ],
    );
  }
}

const String _kTitle = 'Change who\'s paying';
const String _kIntro =
    'One card, one invoice. Switching the payer starts the run over — the '
    'roster is rebuilt around whoever pays, so plans picked so far are '
    'cleared.';
const String _kSelfPay = 'Member getting a membership — pays for themselves';
const String _kAuthorized = 'Authorized payer for this member';
const String _kCreateTitle = 'Add someone new as the payer';
const String _kCreateBody =
    'Creates their profile, then authorizes them to pay for this member.';
const String _kLinkTitle = 'Find an existing member';
const String _kLinkBody =
    'Search the roster, then authorize them to pay for this member.';
const String _kConfirm = 'Use this payer';
const String _kCancel = 'Cancel';
