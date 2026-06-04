import 'package:equatable/equatable.dart';

import 'package:crm/features/members_list/data/models/member_row.dart';

/// States for the dashboard Overdue Payments section.
sealed class OverduePaymentsState extends Equatable {
  const OverduePaymentsState();

  @override
  List<Object?> get props => [];
}

class OverduePaymentsInitial extends OverduePaymentsState {
  const OverduePaymentsInitial();
}

class OverduePaymentsLoading extends OverduePaymentsState {
  const OverduePaymentsLoading();
}

/// Loaded overdue members plus the authoritative overdue
/// count from the counts endpoint (used for the subtitle).
class OverduePaymentsLoaded extends OverduePaymentsState {
  final List<OverdueViewRow> rows;
  final int overdueCount;

  const OverduePaymentsLoaded({
    required this.rows,
    required this.overdueCount,
  });

  @override
  List<Object?> get props => [rows, overdueCount];
}

class OverduePaymentsError extends OverduePaymentsState {
  final String message;
  final String gymId;

  const OverduePaymentsError(
    this.message, {
    required this.gymId,
  });

  @override
  List<Object?> get props => [message, gymId];
}
