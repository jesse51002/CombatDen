import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'waiver_signature_response.g.dart';

/// A recorded e-signature row returned by
/// `POST /api/v1/waivers/{waiver_id}/signatures`.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class WaiverSignatureResponse extends Equatable {
  final String signatureId;
  final String waiverId;
  final String waiverVersionId;
  final String memberId;
  final String gymId;
  final DateTime signedAt;
  final String signerName;
  final String signatureType;

  const WaiverSignatureResponse({
    required this.signatureId,
    required this.waiverId,
    required this.waiverVersionId,
    required this.memberId,
    required this.gymId,
    required this.signedAt,
    required this.signerName,
    required this.signatureType,
  });

  factory WaiverSignatureResponse.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$WaiverSignatureResponseFromJson(json);

  @override
  List<Object?> get props => [
        signatureId,
        waiverId,
        waiverVersionId,
        memberId,
        gymId,
        signedAt,
        signerName,
        signatureType,
      ];
}
