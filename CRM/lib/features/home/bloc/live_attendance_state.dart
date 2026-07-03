import 'package:equatable/equatable.dart';

import 'package:crm/features/home/data/live_attendance_section.dart';

sealed class LiveAttendanceState extends Equatable {
  const LiveAttendanceState();

  @override
  List<Object?> get props => [];
}

class LiveAttendanceInitial extends LiveAttendanceState {
  const LiveAttendanceInitial();
}

class LiveAttendanceLoading extends LiveAttendanceState {
  const LiveAttendanceLoading();
}

/// The card's data: the in-session occurrences' rosters, or — when nothing
/// is live — the next upcoming occurrence's reservations ([isNextPreview]).
/// [sections] empty with [isNextPreview] true means the gym has no upcoming
/// classes at all.
class LiveAttendanceLoaded extends LiveAttendanceState {
  final List<LiveAttendanceSection> sections;

  /// True when no class is in session and [sections] holds the NEXT
  /// occurrence's reservations instead (the fall-forward preview).
  final bool isNextPreview;

  const LiveAttendanceLoaded({
    required this.sections,
    required this.isNextPreview,
  });

  /// Checked-in members across every shown section.
  int get checkedIn =>
      sections.fold(0, (sum, s) => sum + s.checkedIn);

  /// Reserved-but-not-checked-in members across every shown section.
  int get notArrived =>
      sections.fold(0, (sum, s) => sum + s.notArrived);

  @override
  List<Object?> get props => [sections, isNextPreview];
}

class LiveAttendanceError extends LiveAttendanceState {
  final String message;

  /// Carried so the error view's retry can re-dispatch the load.
  final String gymId;

  const LiveAttendanceError(this.message, {required this.gymId});

  @override
  List<Object?> get props => [message, gymId];
}
