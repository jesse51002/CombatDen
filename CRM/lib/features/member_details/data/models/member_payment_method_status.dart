import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'member_payment_method_status.g.dart';

/// Response from `GET /api/v1/members/{member_id}/payment-method-status` —
/// whether this member already has ANY payment method attached to their
/// Stripe customer.
///
/// It is the kiosk's payer gate: the kiosk may only ever charge a card
/// entered during the current signup, so an existing member may pay only
/// while [hasPaymentMethod] is false. [hasPaymentMethod] is REQUIRED on
/// purpose — a body without it fails to parse, the read throws, and the
/// caller's fail-closed path treats that as "not eligible". A defaulted
/// `false` would read a broken response as "no card on file", which is the
/// one wrong answer this model must never be able to give.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MemberPaymentMethodStatus extends Equatable {
  final bool hasPaymentMethod;

  const MemberPaymentMethodStatus({required this.hasPaymentMethod});

  factory MemberPaymentMethodStatus.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$MemberPaymentMethodStatusFromJson(json);

  @override
  List<Object?> get props => [hasPaymentMethod];
}
