import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/shared/wizard_pill.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_buy_row.dart';

/// Where one signature stands in the run.
enum WizardWaiverMark { signed, signingNow, next }

/// One line of the run list: the document, whose signature it is, and where it
/// stands.
typedef WizardWaiverEntry = ({
  String name,
  String memberName,
  WizardWaiverMark mark,
});

/// The WHOLE run's waiver list, on every waiver screen.
///
/// It is listed rather than counted because a parent signing four documents
/// for two children needs to see which ones are left and for whom — a bare
/// "waiver 2 of 4" says how many but never who. Signed entries stay on the
/// list and stay marked: dropping them would make the list shrink under
/// somebody mid-run.
class WizardWaiversRunGroup extends StatelessWidget {
  final List<WizardWaiverEntry> entries;

  const WizardWaiversRunGroup({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(WizardWaiversCopy.runEyebrow, style: scale.eyebrow),
        for (final entry in entries)
          Row(
            spacing: DesignConstants.spacingMedium,
            children: [
              Expanded(
                child: FlowBuyRow(
                  name: entry.name,
                  rule: WizardWaiversCopy.forMember(entry.memberName),
                ),
              ),
              WizardPill(
                label: switch (entry.mark) {
                  WizardWaiverMark.signed => WizardWaiversCopy.signedPill,
                  WizardWaiverMark.signingNow =>
                    WizardWaiversCopy.signingNowPill,
                  WizardWaiverMark.next => WizardWaiversCopy.nextPill,
                },
                tone: switch (entry.mark) {
                  WizardWaiverMark.signed => WizardPillTone.good,
                  WizardWaiverMark.signingNow => WizardPillTone.loud,
                  WizardWaiverMark.next => WizardPillTone.quiet,
                },
              ),
            ],
          ),
      ],
    );
  }
}
