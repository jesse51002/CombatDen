import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'authorized_payer_waiver.g.dart';

/// The gym's default authorized-payer waiver a payer must sign to be
/// authorized for a member, returned by
/// `GET /api/v1/members/{member_id}/authorized-payer-waiver`.
///
/// Mirrors the backend `AuthorizedPayerWaiverResponse`: identity ([waiverId] /
/// [versionId] / [name]) plus the current version's [body] for the sign dialog
/// to display. The link call records the signature against this same current
/// version server-side, so the UI only echoes back the signer's name + consent.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class AuthorizedPayerWaiver extends Equatable {
  final String waiverId;
  final String versionId;
  final String name;
  final String body;

  const AuthorizedPayerWaiver({
    required this.waiverId,
    required this.versionId,
    required this.name,
    required this.body,
  });

  factory AuthorizedPayerWaiver.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$AuthorizedPayerWaiverFromJson(json);

  @override
  List<Object?> get props => [waiverId, versionId, name, body];
}
