/// The flow's GATHERED reads — the ones it makes for several people at once.
///
/// Both run concurrently and neither can throw. `Future.wait` propagates the
/// FIRST error and discards every sibling's answer, so one flaky member would
/// otherwise cost the whole family theirs; catching per member makes the
/// gathered list total. The old wizard instead awaited each member in turn,
/// which made a four-person family four round trips deep before the plans step
/// could say anything.
///
/// The two answers deliberately fail in OPPOSITE directions, and the types say
/// so: a missing membership detail leaves a person UNGATED (fail-open — the
/// backend still refuses a duplicate, and blocking a legitimate sale is the
/// worse error), while a missing waiver answer leaves every waiver ON the
/// queue (fail-closed — a needless signature costs twenty seconds, a missing
/// one voids the gym's protection).
library;

import 'dart:developer';

import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';

/// One member's detail, or null when the read did not land.
typedef WizardDetailAnswer = ({
  String memberId,
  MemberDetailResponse? detail,
});

/// One member's compliant signatures. `satisfied == null` is the fail-CLOSED
/// signal and differs from an empty set: null means the read did not land, so
/// NOTHING may be skipped for them; empty means the server answered and named
/// nothing compliant. Carrying that in the TYPE is what stops a caller
/// collapsing the two.
typedef WizardWaiverAnswer = ({String memberId, Set<String>? satisfied});

/// Every member's detail, read at once. Members whose read failed are simply
/// absent from the result.
Future<Map<String, MemberDetailResponse>> gatherMemberDetails(
  MemberRepository repository,
  Iterable<String> memberIds,
) async {
  final wanted = memberIds.toSet();
  if (wanted.isEmpty) return const {};
  final answers = await Future.wait(
    wanted.map((id) => _readDetail(repository, id)),
  );
  return {
    for (final answer in answers) answer.memberId: ?answer.detail,
  };
}

Future<WizardDetailAnswer> _readDetail(
  MemberRepository repository,
  String memberId,
) async {
  try {
    return (memberId: memberId, detail: await repository.getMemberDetail(memberId));
  } catch (e, st) {
    log(
      'Membership wizard: member detail read failed (no client-side plan '
      'gates for this member)',
      error: e,
      stackTrace: st,
    );
    return (memberId: memberId, detail: null);
  }
}

/// Per member, the waivers the gym ALREADY holds a compliant signature for.
///
/// `signed && meets_floor` and nothing else: `meets_floor` is the SERVER's own
/// compliance verdict — the same rule the 422 purchase gate applies — and the
/// re-sign floor is never re-derived here. A row signed BELOW the floor is
/// exactly the re-sign case and stays on the queue.
///
/// A member whose read failed is ABSENT from the result, which is what makes
/// the skip fail closed: no entry means no waiver is skipped for them.
Future<Map<String, Set<String>>> gatherSatisfiedWaivers({
  required MembershipsRepository repository,
  required String gymId,
  required Iterable<String> memberIds,
}) async {
  final wanted = memberIds.toSet();
  if (wanted.isEmpty) return const {};
  final answers = await Future.wait(
    wanted.map((id) => _readSatisfied(repository, gymId, id)),
  );
  return {
    for (final answer in answers) answer.memberId: ?answer.satisfied,
  };
}

Future<WizardWaiverAnswer> _readSatisfied(
  MembershipsRepository repository,
  String gymId,
  String memberId,
) async {
  try {
    final rows = await repository.listMemberWaiverStatus(memberId, gymId);
    return (
      memberId: memberId,
      satisfied: <String>{
        for (final row in rows)
          if (row.signed && row.meetsFloor) row.waiverId,
      },
    );
  } catch (e, st) {
    log(
      'Membership wizard: prior waiver status read failed (every waiver on '
      'the plan will be asked for)',
      error: e,
      stackTrace: st,
    );
    return (memberId: memberId, satisfied: null);
  }
}
