import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'member_memberships_start_payment.g.dart';

/// A card entered at checkout for a start request — mirrors the
/// backend `MemberMembershipsStartPayment`.
///
/// [paymentMethodId] is the Stripe PaymentMethod (`pm_…`).
/// [setDefault] promotes it to the payer's saved default before
/// charging (required by the backend when the cart has a recurring
/// membership; optional for a purely one-time cart, where `false`
/// means a one-off card the backend never saves).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
  explicitToJson: true,
)
class MemberMembershipsStartPayment extends Equatable {
  final String paymentMethodId;
  final bool setDefault;

  const MemberMembershipsStartPayment({
    required this.paymentMethodId,
    this.setDefault = false,
  });

  Map<String, dynamic> toJson() =>
      _$MemberMembershipsStartPaymentToJson(this);

  @override
  List<Object?> get props => [paymentMethodId, setDefault];
}
