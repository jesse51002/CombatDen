import 'package:mobile_app/features/member_select/data/models/member_identity.dart';

/// The outcome of the boot revalidation ladder — what the gate should do given
/// the persisted selection and the fresh member list.
enum MemberSelectionOutcome {
  /// The persisted member is still in the fresh list → restore it silently.
  restore,

  /// No valid persisted member, but exactly one row → auto-select it.
  autoSelect,

  /// No valid persisted member and 2+ rows → show the picker.
  picker,

  /// No rows at all → the no-membership state.
  empty,
}

/// The decision plus, for [restore] / [autoSelect], the member to select.
class MemberSelectionDecision {
  final MemberSelectionOutcome outcome;
  final MemberIdentity? member;

  const MemberSelectionDecision(this.outcome, [this.member]);
}

/// The boot **revalidation ladder**, as a pure function so it can be tested
/// without widgets:
///
/// - persisted id present in the fresh list → [restore] that row silently;
/// - missing (or no persisted id) → then exactly one row → [autoSelect];
/// - 2+ rows → [picker];
/// - 0 rows → [empty] (the no-membership state).
///
/// A stale persisted id is simply dropped: it falls through to the count-based
/// branches as if none had been persisted.
MemberSelectionDecision resolveMemberSelection({
  required String? persistedId,
  required List<MemberIdentity> members,
}) {
  if (members.isEmpty) {
    return const MemberSelectionDecision(MemberSelectionOutcome.empty);
  }
  if (persistedId != null) {
    for (final m in members) {
      if (m.memberId == persistedId) {
        return MemberSelectionDecision(MemberSelectionOutcome.restore, m);
      }
    }
  }
  if (members.length == 1) {
    return MemberSelectionDecision(
      MemberSelectionOutcome.autoSelect,
      members.first,
    );
  }
  return const MemberSelectionDecision(MemberSelectionOutcome.picker);
}
