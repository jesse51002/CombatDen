import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'waiver_signatory_row.g.dart';

/// One row of a per-waiver signature roster, from
/// `GET /api/v1/waivers/{waiver_id}/signatures`: a gym member
/// and their latest sign status for that waiver.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class WaiverSignatoryRow extends Equatable {
  final String memberId;
  final String firstName;
  final String lastName;
  @JsonKey(defaultValue: false)
  final bool signed;
  final DateTime? signedAt;
  final String? waiverVersionId;
  final int? versionNumber;
  @JsonKey(defaultValue: false)
  final bool signedCurrentVersion;

  const WaiverSignatoryRow({
    required this.memberId,
    required this.firstName,
    required this.lastName,
    this.signed = false,
    this.signedAt,
    this.waiverVersionId,
    this.versionNumber,
    this.signedCurrentVersion = false,
  });

  String get fullName => '$firstName $lastName'.trim();

  factory WaiverSignatoryRow.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$WaiverSignatoryRowFromJson(json);

  @override
  List<Object?> get props => [
        memberId,
        firstName,
        lastName,
        signed,
        signedAt,
        waiverVersionId,
        versionNumber,
        signedCurrentVersion,
      ];
}
