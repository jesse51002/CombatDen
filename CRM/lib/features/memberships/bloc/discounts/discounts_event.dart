import 'package:equatable/equatable.dart';

import 'package:crm/features/memberships/data/models/discount_create_request.dart';
import 'package:crm/features/memberships/data/models/discount_update_request.dart';

sealed class DiscountsEvent extends Equatable {
  const DiscountsEvent();

  @override
  List<Object?> get props => [];
}

/// Load (or reload) the gym's discount presets.
class DiscountsInitRequested extends DiscountsEvent {
  final String gymId;

  const DiscountsInitRequested(this.gymId);

  @override
  List<Object?> get props => [gymId];
}

class DiscountCreated extends DiscountsEvent {
  final DiscountCreateRequest request;

  const DiscountCreated(this.request);
}

class DiscountUpdated extends DiscountsEvent {
  final DiscountUpdateRequest request;

  const DiscountUpdated(this.request);
}

class DiscountDeleted extends DiscountsEvent {
  final String discountId;
  final String gymId;

  const DiscountDeleted({required this.discountId, required this.gymId});

  @override
  List<Object?> get props => [discountId, gymId];
}
