import 'package:equatable/equatable.dart';

/// One signature this run still owes — a (person, waiver) pair.
///
/// The queue is derived PROACTIVELY from the plans that were picked, so the
/// step appears before the money rather than after a 422. A task is keyed on
/// the MEMBER as well as the waiver: the same document is still owed by the
/// next child on the roster, so signing it once for one person clears exactly
/// one entry.
class MembershipWizardWaiverTask extends Equatable {
  final String memberId;

  /// Whose signature it is, for the panel's banner.
  final String memberName;

  final String waiverId;

  /// The gym's name for the waiver where it is already known — the server gate
  /// names it, the plan's `waiver_ids` do not. Null until the body is read.
  final String? waiverName;

  /// The SERVER named this pair at a 422 gate. Such a task can never be
  /// dropped by the client-side already-signed skip: the backend is
  /// authoritative about what it will refuse.
  final bool serverGated;

  const MembershipWizardWaiverTask({
    required this.memberId,
    required this.memberName,
    required this.waiverId,
    this.waiverName,
    this.serverGated = false,
  });

  /// The identity a signature is recorded against.
  String get key => '$memberId:$waiverId';

  @override
  List<Object?> get props => [
        memberId,
        memberName,
        waiverId,
        waiverName,
        serverGated,
      ];
}
