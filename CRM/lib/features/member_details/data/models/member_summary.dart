import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'member_summary.g.dart';

/// Lightweight member data for the right sidebar list.
///
/// Member-id keyed. Built from `MemberListItem` rows
/// returned by `POST /api/v1/members/list` (see
/// `MemberRepository.getAllMembers`).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MemberSummary extends Equatable {
  final String memberId;
  final String firstName;
  final String lastName;
  final String? photoUrl;

  const MemberSummary({
    required this.memberId,
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
        memberId,
        firstName,
        lastName,
        photoUrl,
      ];
}
