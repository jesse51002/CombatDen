import 'package:equatable/equatable.dart';

import 'package:crm/features/memberships/data/models/waiver_create_request.dart';
import 'package:crm/features/memberships/data/models/waiver_update_request.dart';

sealed class WaiversEvent extends Equatable {
  const WaiversEvent();

  @override
  List<Object?> get props => [];
}

/// Load (or reload) the gym's waivers.
class WaiversInitRequested extends WaiversEvent {
  final String gymId;

  const WaiversInitRequested(this.gymId);

  @override
  List<Object?> get props => [gymId];
}

class WaiverCreated extends WaiversEvent {
  final WaiverCreateRequest request;

  const WaiverCreated(this.request);
}

class WaiverUpdated extends WaiversEvent {
  final WaiverUpdateRequest request;

  const WaiverUpdated(this.request);
}

class WaiverDeleted extends WaiversEvent {
  final String waiverId;
  final String gymId;

  const WaiverDeleted({required this.waiverId, required this.gymId});

  @override
  List<Object?> get props => [waiverId, gymId];
}
