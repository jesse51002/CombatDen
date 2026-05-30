/// View models for the dashboard's "Upcoming Classes" card.
///
/// Populated live from the selected gym's classes by
/// `upcoming_classes_generator.dart` — the gym feed serves the class image as
/// a network URL, so [ScheduledClass] carries an [imageUrl] (not a bundled
/// asset). The first class of the first day can be flagged [inSession] to
/// highlight it in the primary accent. Field names mirror what a real API
/// would return so the future swap to a repository is mechanical.
class ScheduledClass {
  final String id;
  final String name;
  final String startTime;
  final String endTime;
  final String durationLabel;
  final String instructorName;
  final int? attendingCount;
  final int? checkedInCount;
  final bool inSession;
  final String? imageUrl;

  const ScheduledClass({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.durationLabel,
    required this.instructorName,
    this.attendingCount,
    this.checkedInCount,
    this.inSession = false,
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
