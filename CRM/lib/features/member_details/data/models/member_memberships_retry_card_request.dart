import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'member_memberships_retry_card_request.g.dart';

/// Body for `POST /api/v1/member_memberships/retry-card`.
///
/// Mirrors the mark-paid-cash body exactly (member-id keyed:
/// the membership item, the covered member, an idempotency
/// key) — the two are the pair of settlement actions on an
/// overdue membership's open invoice. Retry takes NO card:
/// the backend charges the payer's DEFAULT card on file.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class MemberMembershipsRetryCardRequest extends Equatable {
  final String itemId;
  final String memberId;
  final String idempotencyKey;

  const MemberMembershipsRetryCardRequest({
    required this.itemId,
    required this.memberId,
    required this.idempotencyKey,
  });

  Map<String, dynamic> toJson() =>
      _$MemberMembershipsRetryCardRequestToJson(this);

  @override
  @JsonKey(includeToJson: false)
  List<Object?> get props => [
        itemId,
        memberId,
        idempotencyKey,
      ];

  @override
  @JsonKey(includeToJson: false)
  bool? get stringify => super.stringify;

  @override
  @JsonKey(includeToJson: false)
  int get hashCode => super.hashCode; // ignore: hash_and_equals
}
