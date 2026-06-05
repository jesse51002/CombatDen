import 'package:equatable/equatable.dart';

import 'package:crm/features/member_details/data/models/membership_plan_response.dart';

sealed class PlansState extends Equatable {
  const PlansState();

  @override
  List<Object?> get props => [];
}

class PlansInitial extends PlansState {
  const PlansInitial();
}

class PlansLoading extends PlansState {
  const PlansLoading();
}

class PlansLoaded extends PlansState {
  final String gymId;
  final List<MembershipPlanResponse> plans;

  /// True while a create/update/delete is in flight.
  final bool isMutating;

  /// Set when the last mutation failed; cleared on the next load.
  final String? actionError;

  const PlansLoaded({
    required this.gymId,
    required this.plans,
    this.isMutating = false,
    this.actionError,
  });

  PlansLoaded copyWith({
    List<MembershipPlanResponse>? plans,
    bool? isMutating,
    String? actionError,
  }) {
    return PlansLoaded(
      gymId: gymId,
      plans: plans ?? this.plans,
      isMutating: isMutating ?? this.isMutating,
      actionError: actionError,
    );
  }

  @override
  List<Object?> get props => [gymId, plans, isMutating, actionError];
}

class PlansError extends PlansState {
  final String message;
  final String gymId;

  const PlansError(this.message, {required this.gymId});

  @override
  List<Object?> get props => [message, gymId];
}
