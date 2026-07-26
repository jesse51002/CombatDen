import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_option_row.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_detail_group.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_field_pair.dart';

/// ADD SOMEONE — the ONE adder pair on the run.
///
/// Both rows point the same way (authorize the payer for somebody new), and
/// each states what choosing it does on the row itself. That is the fix for
/// the old flow's worst confusion: two adder pairs across two steps, worded
/// identically and meaning opposite things.
class WhoAddGroup extends StatelessWidget {
  final String payerName;
  final VoidCallback onAddNew;
  final VoidCallback onLinkExisting;

  const WhoAddGroup({
    super.key,
    required this.payerName,
    required this.onAddNew,
    required this.onLinkExisting,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return FlowDetailGroup(
      eyebrow: WizardWhoCopy.addEyebrow,
      children: [
        FlowFieldPair(
          children: [
            WizardOptionRow(
              icon: Symbols.person_add_sharp,
              title: WizardWhoCopy.addNewTitle,
              meta: WizardWhoCopy.addNewBody(payerName),
              opensMore: true,
              onTap: onAddNew,
            ),
            WizardOptionRow(
              icon: Symbols.search_sharp,
              title: WizardWhoCopy.findExistingTitle,
              meta: WizardWhoCopy.findExistingBody(payerName),
              opensMore: true,
              onTap: onLinkExisting,
            ),
          ],
        ),
        Text(
          WizardWhoCopy.ownEmailNote,
          style: scale.caption.copyWith(color: DesignConstants.text2nd),
        ),
      ],
    );
  }
}
