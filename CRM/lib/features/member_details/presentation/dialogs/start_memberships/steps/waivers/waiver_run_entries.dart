/// The whole run's waiver list, as the panel renders it.
///
/// The queue itself never carries a document's NAME (only a 422 gate names
/// one), so the step remembers each name as its body loads and this reads that
/// memo. A row whose name is still unknown says so with the copy's own word
/// rather than rendering an empty line — the row is still real, and its owner
/// still owes the signature.
library;

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/waivers/waivers_run_group.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';

/// One entry per (person, waiver) the run owes, in queue order, each marked
/// signed / signing now / still to come.
List<WizardWaiverEntry> wizardWaiverEntries(
  MembershipWizardState state,
  Map<String, String> seenNames,
) {
  final current = state.currentWaiverTask;
  return [
    for (final task in state.waiverQueue)
      (
        name: task.waiverName ??
            seenNames[task.waiverId] ??
            WizardWaiversCopy.unnamedWaiver,
        memberName: task.memberName,
        mark: state.signedWaiverKeys.contains(task.key)
            ? WizardWaiverMark.signed
            : task.key == current?.key
                ? WizardWaiverMark.signingNow
                : WizardWaiverMark.next,
      ),
  ];
}
