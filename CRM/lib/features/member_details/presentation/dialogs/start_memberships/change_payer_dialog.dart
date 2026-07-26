import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_person.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/change_payer_copy.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/change_payer_options.dart';
import 'package:crm/features/membership_flow/config/membership_flow_scale.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/config/staff_flow_copy.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// Who pays for this run — a separate task with its own commit, so a dialog.
///
/// It is the `who` step's two adders pointed the OTHER way, which is precisely
/// why they no longer sit side by side on one screen: the old wizard offered
/// "add a payer" and "add a payee" as two identical-looking pairs on adjacent
/// steps, and staff picked the wrong one. Here the payee adders live on the
/// roster and the payer adders live behind this one named button.
///
/// It reads the run's OWN state rather than a list handed in at open: a payer
/// authorized while this dialog is up must appear in it, and a snapshot taken
/// at `show()` time can never carry them — which is what left staff looking at
/// a popup that had quietly moved on without them.
///
/// It pops the chosen member id, or null when nothing changed. The CALLER
/// applies it — and applying it rebuilds the run, which the button that opens
/// this dialog says before it is pressed.
class ChangePayerDialog extends StatefulWidget {
  /// The member whose page opened the run. They are always a valid payer
  /// (self-pay), and every authorization offered here is written FOR them.
  final MemberDetailResponse launchMember;

  /// Create a new member and authorize them AS a payer. Resolves to their id.
  final Future<String?> Function() onCreatePayer;

  /// Pick an existing member and authorize them AS a payer.
  final Future<String?> Function() onLinkPayer;

  /// Authorize somebody ALREADY on the run's roster as a payer — the same
  /// signature [onLinkPayer] collects, with the search skipped because the
  /// person is already named.
  final Future<String?> Function(MembershipWizardPerson person) onAuthorizeInRun;

  const ChangePayerDialog({
    super.key,
    required this.launchMember,
    required this.onCreatePayer,
    required this.onLinkPayer,
    required this.onAuthorizeInRun,
  });

  static Future<String?> show({
    required BuildContext context,
    required MembershipWizardCubit cubit,
    required MemberDetailResponse launchMember,
    required Future<String?> Function() onCreatePayer,
    required Future<String?> Function() onLinkPayer,
    required Future<String?> Function(MembershipWizardPerson person)
        onAuthorizeInRun,
  }) {
    return showDialog<String>(
      context: context,
      // The run's state, INTO the dialog's own subtree: `showDialog` builds
      // outside the wizard's, so without this the dialog could never rebuild
      // on a candidate list that changed under it.
      builder: (_) => BlocProvider<MembershipWizardCubit>.value(
        value: cubit,
        child: ChangePayerDialog(
          launchMember: launchMember,
          onCreatePayer: onCreatePayer,
          onLinkPayer: onLinkPayer,
          onAuthorizeInRun: onAuthorizeInRun,
        ),
      ),
    );
  }

  @override
  State<ChangePayerDialog> createState() => _ChangePayerDialogState();
}

class _ChangePayerDialogState extends State<ChangePayerDialog> {
  /// Null until staff pick somebody — the current payer is the answer until
  /// then, and reading it off the run rather than copying it keeps the two
  /// from disagreeing.
  String? _picked;

  /// A just-authorized payer is auto-selected: staff went to the trouble of
  /// adding them, and making them hunt for the row they just created is the
  /// kind of small insult that teaches people to distrust a flow.
  Future<void> _add(Future<String?> Function() authorize) async {
    final added = await authorize();
    if (added == null || !mounted) return;
    setState(() => _picked = added);
  }

  /// Whether [_picked] is a payer the run would actually take — the launch
  /// member, or somebody now authorized for them. It mirrors the cubit's own
  /// rule, so a confirm can never pop an id `selectPayer` would drop on the
  /// floor.
  bool _canConfirm(MembershipWizardState state) {
    final picked = _picked;
    if (picked == null || picked == state.payer.memberId) return false;
    return picked == state.launchMemberId ||
        state.payerCandidates.any((a) => a.memberId == picked);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MembershipWizardCubit, MembershipWizardState>(
      builder: (context, state) {
        return MembershipFlowTheme(
          scale: const MembershipFlowScale.admin(),
          copy: const StaffFlowCopy(),
          child: AppDialog(
            title: ChangePayerCopy.title,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingLarge,
              children: [
                Text(
                  ChangePayerCopy.intro,
                  style: DesignConstants.p.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
                ChangePayerOptions(
                  launchMemberId: state.launchMemberId,
                  launchMemberName: widget.launchMember.fullName,
                  authorized: state.payerCandidates,
                  inRun: state.unauthorizedRosterPayers,
                  selected: _picked ?? state.payer.memberId,
                  onSelect: (id) => setState(() => _picked = id),
                  onAuthorize: (person) =>
                      _add(() => widget.onAuthorizeInRun(person)),
                  onCreate: () => _add(widget.onCreatePayer),
                  onLink: () => _add(widget.onLinkPayer),
                ),
              ],
            ),
            actions: AppDialogActions(
              primaryLabel: ChangePayerCopy.confirm,
              primaryOnPressed: _canConfirm(state)
                  ? () => Navigator.of(context).pop(_picked)
                  : null,
              secondaryLabel: ChangePayerCopy.cancel,
              secondaryOnPressed: () => Navigator.of(context).pop(),
            ),
          ),
        );
      },
    );
  }
}
