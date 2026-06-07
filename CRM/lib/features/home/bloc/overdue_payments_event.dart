import 'package:equatable/equatable.dart';

/// Events for the dashboard Overdue Payments section.
sealed class OverduePaymentsEvent extends Equatable {
  const OverduePaymentsEvent();

  @override
  List<Object?> get props => [];
}

/// Load (or reload) the overdue members for [gymId].
class OverduePaymentsLoadRequested extends OverduePaymentsEvent {
  final String gymId;

  const OverduePaymentsLoadRequested(this.gymId);

  @override
  List<Object?> get props => [gymId];
}
