import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/members_list/data/models/membership_status.dart';

part 'paying_for_member.g.dart';

/// A member on a plan with their class usage for the
/// current cycle.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class PayingForMember extends Equatable {
  final String crmUserId;
  final String firstName;
  final String lastName;
  final String? photoUrl;
  @JsonKey(fromJson: MembershipStatus.fromJson)
  final MembershipStatus status;
  final int? classCount;
  @JsonKey(defaultValue: 0)
  final int classesUsed;
  final int? classesRemaining;

  const PayingForMember({
    required this.crmUserId,
    required this.firstName,
    required this.lastName,
    this.photoUrl,
    required this.status,
    this.classCount,
    this.classesUsed = 0,
    this.classesRemaining,
  });

  factory PayingForMember.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$PayingForMemberFromJson(json);

  String get fullName => '$firstName $lastName';

  @override
  List<Object?> get props => [
        crmUserId,
        firstName,
        lastName,
        photoUrl,
        status,
        classCount,
        classesUsed,
        classesRemaining,
      ];
}
