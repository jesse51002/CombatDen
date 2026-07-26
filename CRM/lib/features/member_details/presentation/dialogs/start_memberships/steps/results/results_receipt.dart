import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_outcome.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_result_item.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_status.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/results/results_labels.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_form_panel.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_inline_notice.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_result_row.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_two_charges_note.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// Frames 10 and 11 — one row per membership, never a single summary line.
///
/// The run was per-membership and so is its receipt. On a partial, EVERY row
/// stays visible and marked: the two that worked are not dropped to make room
/// for the two that did not, because a row removed from a receipt is
/// indistinguishable from a membership nobody was told about. Marks are warm,
/// never red — the failures are recoverable and the money that moved is safe.
class WizardResultsReceipt extends StatelessWidget {
  final MembershipWizardState state;

  /// Open that member's own page — the only navigation the wizard performs.
  final ValueChanged<String> onViewMember;

  const WizardResultsReceipt({
    super.key,
    required this.state,
    required this.onViewMember,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final items = state.startItems;
    final partial = state.outcome != MembershipWizardOutcome.allCreated;
    return FlowFormPanel(
      children: [
        if (partial)
          const FlowInlineNotice(message: WizardResultsCopy.partialNote),
        Text(WizardResultsCopy.startedEyebrow, style: scale.eyebrow),
        for (final item in items)
          _Row(state: state, item: item, onViewMember: onViewMember),
        const Hairline(),
        if (state.chargedTwice) const FlowTwoChargesNote(),
        Text(
          WizardResultsCopy.openProfile,
          style: scale.caption.copyWith(color: DesignConstants.text2nd),
        ),
      ],
    );
  }
}

/// One membership's outcome. A CREATED row is a tap target onto that member's
/// profile; a failed or unconfirmed one is not — there is nothing to look at
/// yet, and offering the jump would imply there is.
class _Row extends StatelessWidget {
  final MembershipWizardState state;
  final MemberMembershipsStartResultItem item;
  final ValueChanged<String> onViewMember;

  const _Row({
    required this.state,
    required this.item,
    required this.onViewMember,
  });

  @override
  Widget build(BuildContext context) {
    final row = FlowResultRow(
      label: wizardResultLabel(state, item),
      status: item.status,
      // The backend's own reason, which is what the desk has to act on: a
      // decline needs a different next move from a timeout. It is the one
      // line a lobby iPad may never print, so it arrives from the HOST.
      detail: item.error,
    );
    if (item.status != MemberMembershipsStartStatus.created) return row;
    return Semantics(
      button: true,
      label: WizardResultsCopy.openMemberSemantic(
        wizardResultMemberName(state, item),
      ),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onViewMember(item.memberId),
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        child: row,
      ),
    );
  }
}
