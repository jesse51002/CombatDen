/// The staff flow's waiver RUN, derived rather than discovered.
///
/// The old wizard learned which signatures were missing only when the money
/// call came back 422, which put a legal step after the price and made a
/// signature look like an error. Here the queue is built from the plans that
/// were picked, the moment they are picked, so the step exists before the
/// money — and the 422 stays the backstop that makes a client-side skip safe
/// at all.
///
/// Pure: the reads that feed it (`satisfiedWaiverIds`, the gate) live in the
/// cubit. Nothing here is async.
library;

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_draft.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_person.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_waiver_task.dart';
import 'package:crm/features/membership_flow/domain/waiver_queue.dart';

/// Every signature this run still owes, in ROSTER order (payer first, exactly
/// as the `who` step lists them) and within a person in plan-pick order.
///
/// The per-person queue is the shared rulebook's ([waiverQueueFor]) — the
/// already-signed skip fails CLOSED there, and only a signature the SERVER
/// positively cleared at or above the re-sign floor ever leaves it. Anything a
/// 422 named is appended for that person whatever their plans say, because a
/// plan whose waiver list drifted from the gate would otherwise loop the desk
/// through a step that never satisfies the backend.
List<MembershipWizardWaiverTask> deriveWaiverQueue({
  required List<MembershipWizardPerson> people,
  required Map<String, List<MembershipWizardDraft>> drafts,
  required Map<String, Set<String>> satisfiedWaiverIds,
  required List<MembershipWizardWaiverTask> serverGate,
}) {
  final tasks = <MembershipWizardWaiverTask>[];
  final gatedByMember = <String, List<MembershipWizardWaiverTask>>{};
  for (final task in serverGate) {
    gatedByMember.putIfAbsent(task.memberId, () => []).add(task);
  }
  final onRoster = {for (final person in people) person.memberId};
  for (final person in people) {
    final gated = gatedByMember[person.memberId] ?? const [];
    // Somebody the request will not carry still signs whatever the SERVER
    // named for them; nothing else.
    final planWaiverIds = person.training
        ? _planWaiverIdsFor(drafts[person.memberId])
        : const <String>[];
    final queue = waiverQueueFor(
      planWaiverIds: planWaiverIds,
      serverGatedWaiverIds: {for (final t in gated) t.waiverId},
      satisfiedWaiverIds:
          satisfiedWaiverIds[person.memberId] ?? const <String>{},
    );
    for (final waiverId in queue) {
      final named = gated.where((t) => t.waiverId == waiverId);
      tasks.add(
        MembershipWizardWaiverTask(
          memberId: person.memberId,
          memberName: person.name,
          waiverId: waiverId,
          waiverName: named.isEmpty ? null : named.first.waiverName,
          serverGated: named.isNotEmpty,
        ),
      );
    }
  }
  // A gate naming somebody the roster no longer holds is still the SERVER
  // refusing this sale. Dropping it because the loop above had nobody to hang
  // it on would leave the desk bouncing off a 422 with no step that answers it.
  for (final task in serverGate) {
    if (onRoster.contains(task.memberId)) continue;
    tasks.add(task);
  }
  return tasks;
}

/// The waivers one person's picked plans require, de-duplicated in pick order
/// — the same document required by two of their memberships is one signature.
List<String> _planWaiverIdsFor(List<MembershipWizardDraft>? drafts) {
  final ids = <String>[];
  for (final draft in drafts ?? const <MembershipWizardDraft>[]) {
    for (final id in draft.plan.waiverIds) {
      if (id.trim().isEmpty || ids.contains(id)) continue;
      ids.add(id);
    }
  }
  return ids;
}

/// The first task in [queue] nobody has signed yet, or null when the run is
/// done. Signed stays signed, so Back then forward lands on the next unsigned
/// one rather than re-asking.
MembershipWizardWaiverTask? firstUnsignedTask(
  List<MembershipWizardWaiverTask> queue,
  Set<String> signedKeys,
) {
  for (final task in queue) {
    if (!signedKeys.contains(task.key)) return task;
  }
  return null;
}

/// The signed set with everything the SERVER just named REMOVED.
///
/// The backend is authoritative about what it will refuse: leaving a
/// client-side "signed" mark on a pair the gate lists would skip the very
/// waiver blocking the sale, and the desk would loop between the money and a
/// step with nothing left to do.
Set<String> signedMinusGate(
  Set<String> signedKeys,
  List<MembershipWizardWaiverTask> gate,
) {
  final named = {for (final task in gate) task.key};
  return {
    for (final key in signedKeys)
      if (!named.contains(key)) key,
  };
}
