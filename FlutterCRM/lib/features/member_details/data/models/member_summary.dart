import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'member_summary.g.dart';

/// Lightweight member data for the right sidebar list.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MemberSummary extends Equatable {
  final String crmUserId;
  final String firstName;
  final String lastName;
  final String? photoUrl;

  const MemberSummary({
    required this.crmUserId,
    required this.firstName,
    required this.lastName,
    this.photoUrl,
  });

  factory MemberSummary.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$MemberSummaryFromJson(json);

  String get fullName => '$firstName $lastName';

  @override
  List<Object?> get props => [
        crmUserId,
        firstName,
        lastName,
        photoUrl,
      ];
}
