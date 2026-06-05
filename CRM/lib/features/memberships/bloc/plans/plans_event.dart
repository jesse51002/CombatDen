import 'package:equatable/equatable.dart';

import 'package:crm/features/memberships/data/models/membership_plan_create_request.dart';
import 'package:crm/features/memberships/data/models/membership_plan_price_request.dart';
import 'package:crm/features/memberships/data/models/membership_plan_update_request.dart';

sealed class PlansEvent extends Equatable {
  const PlansEvent();

  @override
  List<Object?> get props => [];
}

/// Load (or reload) the gym's membership plans.
class PlansInitRequested extends PlansEvent {
  final String gymId;

  const PlansInitRequested(this.gymId);

  @override
  List<Object?> get props => [gymId];
}

class PlanCreated extends PlansEvent {
  final MembershipPlanCreateRequest request;

  const PlanCreated(this.request);
}

class PlanUpdated extends PlansEvent {
  final MembershipPlanUpdateRequest request;

  const PlanUpdated(this.request);
}

class PlanPriceSet extends PlansEvent {
  final MembershipPlanPriceRequest request;

  const PlanPriceSet(this.request);
}

class PlanDeleted extends PlansEvent {
  final String planId;
  final String gymId;

  const PlanDeleted({required this.planId, required this.gymId});

  @override
  List<Object?> get props => [planId, gymId];
}
