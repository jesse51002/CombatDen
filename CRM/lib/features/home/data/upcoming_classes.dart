/// View models for the dashboard's "Upcoming Classes" card.
///
/// Built live from the real schedule feed (the same
/// `GET /api/v1/classes/instances` occurrences the Schedule board reads) by
/// `upcoming_classes_generator.dart`. Each entry carries a pre-formatted
/// [timeLabel] (resolved start–end) and the gym feed's class [imageUrl].
class ScheduledClass {
  final String id;
  final String name;

  /// Pre-formatted resolved time range, e.g. `6:00 PM - 7:00 PM`.
  final String timeLabel;
  final String? instructorName;

  /// Recorded attendance once a `class_history` row exists; null otherwise.
  final int? attendingCount;
  final String? imageUrl;

  const ScheduledClass({
    required this.id,
    required this.name,
    required this.timeLabel,
    this.instructorName,
    this.attendingCount,
    this.imageUrl,
  });
}

class ScheduledClassDayGroup {
  final String dayLabel;
  final List<ScheduledClass> classes;

  const ScheduledClassDayGroup({
    required this.dayLabel,
    required this.classes,
  });
}
