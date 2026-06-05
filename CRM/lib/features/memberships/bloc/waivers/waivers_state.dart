import 'package:equatable/equatable.dart';

import 'package:crm/features/memberships/data/models/waiver_response.dart';

sealed class WaiversState extends Equatable {
  const WaiversState();

  @override
  List<Object?> get props => [];
}

class WaiversInitial extends WaiversState {
  const WaiversInitial();
}

class WaiversLoading extends WaiversState {
  const WaiversLoading();
}

class WaiversLoaded extends WaiversState {
  final String gymId;
  final List<WaiverResponse> waivers;
  final bool isMutating;
  final String? actionError;

  const WaiversLoaded({
    required this.gymId,
    required this.waivers,
    this.isMutating = false,
    this.actionError,
  });

  WaiversLoaded copyWith({
    List<WaiverResponse>? waivers,
    bool? isMutating,
    String? actionError,
  }) {
    return WaiversLoaded(
      gymId: gymId,
      waivers: waivers ?? this.waivers,
      isMutating: isMutating ?? this.isMutating,
      actionError: actionError,
    );
  }

  @override
  List<Object?> get props => [gymId, waivers, isMutating, actionError];
}

class WaiversError extends WaiversState {
  final String message;
  final String gymId;

  const WaiversError(this.message, {required this.gymId});

  @override
  List<Object?> get props => [message, gymId];
}
