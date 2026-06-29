/// Pure view-models for the Schedule screen's week board.
///
/// The board renders the week as a row of day columns; each column holds that
/// day's classes stacked vertically. These types are the rendered shape — a
/// [ScheduleDayGroup] per visible day, each holding [ScheduleClassEntry] cards.
/// They are derived from the backend `EffectiveClassInstance` feed by the board
/// mapper (`schedule_screen.dart`); nothing here talks to the network.
library;

/// One rendered class card in a day column. Built from one effective backend
/// occurrence: [classId] + [classDate] identify this occurrence so a tap can
/// open the manage dialog (edit the class, or cancel just this day); the rest
/// is display data. [instructorPhotoUrl] is intentionally absent — the backend
/// serves no instructor photo, so the avatar falls back to initials.
class ScheduleClassEntry {
  /// The owning `gym_classes` id — carried so a tap can open that class.
  final String classId;

  /// This occurrence's effective local date — the cancel key for a single-day
  /// exception.
  final DateTime classDate;
  final String name;
  final String timeLabel;
  final String? instructorName;
  final String? imageUrl;
  final int? pointsWorth;
  final int? attendingCount;

  /// True when this occurrence is cancelled — the card shows a badge.
  final bool isCancelled;

  const ScheduleClassEntry({
    required this.classId,
    required this.classDate,
    required this.name,
    required this.timeLabel,
    this.instructorName,
    this.imageUrl,
    this.pointsWorth,
    this.attendingCount,
    this.isCancelled = false,
  });
}

/// One day column on the board: a labelled header above that day's cards.
class ScheduleDayGroup {
  final String dayLabel;
  final List<ScheduleClassEntry> classes;

  /// Marks the current day so its column header is highlighted.
  final bool isToday;

  const ScheduleDayGroup({
    required this.dayLabel,
    required this.classes,
    this.isToday = false,
  });
}
