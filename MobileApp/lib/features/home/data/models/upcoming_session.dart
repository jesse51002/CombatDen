import 'package:equatable/equatable.dart';

import 'package:mobile_app/features/home/data/models/class_occurrence.dart';

/// One open reservation, shaped for the "Your upcoming sessions" card.
///
/// Derived by [HomeBloc] from a class-history `upcoming` row, enriched (when
/// the reservation falls inside the loaded board window) with the occurrence's
/// resolved instructor + time. [occurrence] is the matched board occurrence
/// when available (drives the "view" tap into the class detail); null when the
/// reservation is outside the loaded window.
class UpcomingSession extends Equatable {
  const UpcomingSession({
    required this.dayLabel,
    required this.timeLabel,
    required this.className,
    required this.durationMinutes,
    this.mentor,
    this.occurrence,
  });

  final String dayLabel;
  final String timeLabel;
  final String className;
  final int durationMinutes;
  final String? mentor;
  final ClassOccurrence? occurrence;

  @override
  List<Object?> get props =>
      [dayLabel, timeLabel, className, durationMinutes, mentor, occurrence];
}
