import 'package:equatable/equatable.dart';

import 'package:crm/features/member_details/data/models/discount_response.dart';

sealed class DiscountsState extends Equatable {
  const DiscountsState();

  @override
  List<Object?> get props => [];
}

class DiscountsInitial extends DiscountsState {
  const DiscountsInitial();
}

class DiscountsLoading extends DiscountsState {
  const DiscountsLoading();
}

class DiscountsLoaded extends DiscountsState {
  final String gymId;
  final List<DiscountResponse> discounts;
  final bool isMutating;
  final String? actionError;

  const DiscountsLoaded({
    required this.gymId,
    required this.discounts,
    this.isMutating = false,
    this.actionError,
  });

  DiscountsLoaded copyWith({
    List<DiscountResponse>? discounts,
    bool? isMutating,
    String? actionError,
  }) {
    return DiscountsLoaded(
      gymId: gymId,
      discounts: discounts ?? this.discounts,
      isMutating: isMutating ?? this.isMutating,
      actionError: actionError,
    );
  }

  @override
  List<Object?> get props => [gymId, discounts, isMutating, actionError];
}

class DiscountsError extends DiscountsState {
  final String message;
  final String gymId;

  const DiscountsError(this.message, {required this.gymId});

  @override
  List<Object?> get props => [message, gymId];
}
