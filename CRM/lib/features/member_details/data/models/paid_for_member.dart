import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'paid_for_member.g.dart';

/// A beneficiary an invoice was paid FOR (the invoice's `paid_for`).
///
/// Usually just the payer themselves; a parent paying for a child — or a
/// consolidated family invoice — lists each beneficiary, so a payment shows
/// on (and is refundable from) each of their pages.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class PaidForMember extends Equatable {
  final String memberId;
  @JsonKey(defaultValue: '')
  final String firstName;
  @JsonKey(defaultValue: '')
  final String lastName;
  final String? photoUrl;

  const PaidForMember({
    required this.memberId,
    this.firstName = '',
    this.lastName = '',
    this.photoUrl,
  });

  /// The beneficiary's display name.
  String get name => '$firstName $lastName'.trim();

  factory PaidForMember.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$PaidForMemberFromJson(json);

  @override
  List<Object?> get props => [memberId, firstName, lastName, photoUrl];
}
