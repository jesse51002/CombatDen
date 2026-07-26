/// The facts the waivers step's head is built from, read off the run rather
/// than passed down the tree.
///
/// It exists so the step's `build` reads as "ask the copy for the title" — the
/// index into the queue, the plan that REQUIRES this signature and whose
/// signature it is are three different lookups, and doing them inline is how a
/// head ends up counting a queue it no longer matches.
library;

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_person.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_waiver_task.dart';

/// Everything the head interpolates. [index] is ZERO-based, exactly as
/// `MembershipFlowCopy.waiverStepSubtitle` expects.
typedef WizardWaiverHead = ({
  int index,
  int total,
  String? planName,
  String firstName,
  String memberName,
  bool isGroup,
});

/// The head facts for the signature on screen. With the run finished (no task
/// left) it degrades to the counts alone — the step still renders, and a
/// subtitle counting a waiver nobody is signing would be worse than none.
WizardWaiverHead wizardWaiverHead(MembershipWizardState state) {
  final queue = state.waiverQueue;
  final task = state.currentWaiverTask;
  final person = _personOf(state, task?.memberId);
  return (
    index: task == null ? 0 : queue.indexOf(task),
    total: queue.length,
    planName: _planNameFor(state, task),
    firstName: person?.firstName ?? '',
    memberName: task?.memberName ?? person?.name ?? '',
    isGroup: state.people.length > 1,
  );
}

MembershipWizardPerson? _personOf(MembershipWizardState state, String? id) {
  if (id == null) return null;
  for (final person in state.people) {
    if (person.memberId == id) return person;
  }
  return null;
}

/// The membership on this person's lineup that requires [task]'s waiver, or
/// null when nothing they picked lists it — which is the SERVER-gated case,
/// where naming a plan would be an invention.
String? _planNameFor(
  MembershipWizardState state,
  MembershipWizardWaiverTask? task,
) {
  if (task == null) return null;
  for (final draft in state.draftsFor(task.memberId)) {
    if (draft.plan.waiverIds.contains(task.waiverId)) {
      return draft.plan.planName;
    }
  }
  return null;
}
