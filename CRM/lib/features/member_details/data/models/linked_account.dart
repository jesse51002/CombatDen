import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'linked_account.g.dart';

/// A linked family/group member account.
///
/// Mirrors the merged `BillingLinkedAccount` schema
/// (member-id keyed).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class LinkedAccount extends Equatable {
  final String memberId;
  final String firstName;
  final String lastName;
  final String? photoUrl;

  const LinkedAccount({
    required this.memberId,
    required this.firstName,
    required this.lastName,
    this.photoUrl,
  });

  factory LinkedAccount.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$LinkedAccountFromJson(json);

  String get fullName => '$firstName $lastName';

  @override
  List<Object?> get props => [
        memberId,
        firstName,
        lastName,
        photoUrl,
      ];
}
