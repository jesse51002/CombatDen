import 'package:json_annotation/json_annotation.dart';

part 'duplicate_member_match.g.dart';

/// One same-identity member the backend already has, returned in a
/// [DuplicateMemberException] when a create is gated on a duplicate.
///
/// Mirrors the 409 body's `detail.matches[]` shape (member-id keyed,
/// snake_case). [email] / [photoUrl] may be null on the wire; the match is
/// keyed on first+last+email so a matched row always has an email in
/// practice, but parsing stays resilient.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class DuplicateMemberMatch {
  final String memberId;
  final String firstName;
  final String lastName;
  final String? email;
  final String? photoUrl;

  const DuplicateMemberMatch({
    required this.memberId,
    required this.firstName,
    required this.lastName,
    this.email,
    this.photoUrl,
  });

  factory DuplicateMemberMatch.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$DuplicateMemberMatchFromJson(json);

  String get fullName => '$firstName $lastName';
}

/// Thrown by [MemberRepository.createMember] on a 409 whose
/// `detail.code == "duplicate_member"` — an exact same-gym identity
/// (case/space-insensitive first name + last name + email) already exists and
/// the create was not confirmed. Nothing was written; the caller offers
/// "create anyway" (re-send with `allow_duplicate: true`) or "use existing".
///
/// Feature-scoped (not in `core/errors/exceptions.dart`) so the exception can
/// carry the [DuplicateMemberMatch] `json_serializable` model without a
/// core → feature import. Mirrors the `_parseWaiverGate` shape.
class DuplicateMemberException implements Exception {
  final List<DuplicateMemberMatch> matches;

  const DuplicateMemberException(this.matches);

  @override
  String toString() =>
      'DuplicateMemberException(${matches.length} matches)';
}
