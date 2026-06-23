import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'remove_authorization_preview.g.dart';

/// One membership that removing an authorization would cancel.
/// Mirrors backend `RemoveAuthorizationMembership`.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class RemoveAuthorizationMembership extends Equatable {
  final String itemId;
  final String planName;
  final int totalPrice;

  const RemoveAuthorizationMembership({
    required this.itemId,
    required this.planName,
    required this.totalPrice,
  });

  factory RemoveAuthorizationMembership.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$RemoveAuthorizationMembershipFromJson(json);

  @override
  List<Object?> get props => [itemId, planName, totalPrice];
}

/// What removing an authorization will cancel, shown before confirming.
/// Pair-scoped: the path member's live recurring memberships the payer funds,
/// plus the summed monthly that stops. Mirrors backend
/// `RemoveAuthorizationPreview`.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class RemoveAuthorizationPreview extends Equatable {
  @JsonKey(defaultValue: [])
  final List<RemoveAuthorizationMembership> memberships;
  @JsonKey(defaultValue: 0)
  final int totalMonthly;

  const RemoveAuthorizationPreview({
    this.memberships = const [],
    this.totalMonthly = 0,
  });

  factory RemoveAuthorizationPreview.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$RemoveAuthorizationPreviewFromJson(json);

  @override
  List<Object?> get props => [memberships, totalMonthly];
}
