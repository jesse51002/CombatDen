import 'package:equatable/equatable.dart';

import 'package:crm/features/schedule/data/models/attendee_list_response.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';

/// One class occurrence shown on the dashboard's Live Attendance card: the
/// occurrence itself plus its combined roster (everyone signed up OR
/// attended, from `GET /api/v1/checkin/attendees`). Usually one per card;
/// several when classes overlap.
class LiveAttendanceSection extends Equatable {
  final EffectiveClassInstance instance;
  final List<Attendee> attendees;

  const LiveAttendanceSection({
    required this.instance,
    required this.attendees,
  });

  /// Members with a recorded attendance row — the green "Checked In" rows.
  int get checkedIn => attendees.where((a) => a.attended).length;

  /// Members who reserved but haven't checked in — "Not Here" during a live
  /// class, "Reserved" on the next-class preview.
  int get notArrived =>
      attendees.where((a) => a.signedUp && !a.attended).length;

  @override
  List<Object?> get props => [instance, attendees];
}
