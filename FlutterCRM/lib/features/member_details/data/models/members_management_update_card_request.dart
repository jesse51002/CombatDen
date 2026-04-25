import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'members_management_update_card_request.g.dart';

/// Body for `PUT /api/v1/members/{crm_user_id}/card`.
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
  List<Object?> get props => [paymentMethodId];
}
