import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'pays_for_member.g.dart';

/// One recurring membership the viewed member funds — used by the
/// freeze-impact list. Mirrors backend `BillingPaysForMembership`.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class PaysForMembership extends Equatable {
  final String itemId;
  final String planName;

  const PaysForMembership({
    required this.itemId,
    required this.planName,
  });

  factory PaysForMembership.fromJson(Map<String, dynamic> json) =>
      _$PaysForMembershipFromJson(json);

  @override
  List<Object?> get props => [itemId, planName];
}

/// A member whose recurring memberships the viewed member pays for,
/// with the funded membership(s). Freezing the viewed member pauses
/// every membership across the `pays_for` list. Mirrors backend
/// `BillingPaysForMember`.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class PaysForMember extends Equatable {
  final String memberId;
  final String firstName;
  final String lastName;
  final String? photoUrl;
  @JsonKey(defaultValue: [])
  final List<PaysForMembership> memberships;

  const PaysForMember({
    required this.memberId,
    required this.firstName,
    required this.lastName,
    this.photoUrl,
    this.memberships = const [],
  });

  factory PaysForMember.fromJson(Map<String, dynamic> json) =>
      _$PaysForMemberFromJson(json);

  String get fullName => '$firstName $lastName';

  @override
  List<Object?> get props => [
        memberId,
        firstName,
        lastName,
        photoUrl,
        memberships,
      ];
}
