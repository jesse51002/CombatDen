import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'members_management_update_card_request.g.dart';

/// Body for `PUT /api/v1/members/{member_id}/card`.
///
/// Mirrors the merged `MembersBillingUpdateCardRequest`
/// schema (`payment_method_id`).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class MembersManagementUpdateCardRequest extends Equatable {
  final String paymentMethodId;

  const MembersManagementUpdateCardRequest({
    required this.paymentMethodId,
  });

  Map<String, dynamic> toJson() =>
      _$MembersManagementUpdateCardRequestToJson(this);

  @override
  @JsonKey(includeToJson: false)
  List<Object?> get props => [paymentMethodId];

  @override
  @JsonKey(includeToJson: false)
  bool? get stringify => super.stringify;

  @override
  @JsonKey(includeToJson: false)
  int get hashCode => super.hashCode; // ignore: hash_and_equals
}
