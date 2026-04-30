/// Mock data for the "Upcoming Classes" card on the dashboard.
///
/// Classes are grouped by day (e.g. "Today", "Wed 19", "Thr 20") in the
/// UI. The first class of the first group can be flagged `inSession` to
/// highlight it in primary orange. Field names mirror what a real API
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
  final String? imageAsset;

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
    this.imageAsset,
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

const List<ScheduledClassDayGroup> kMockUpcomingClasses = [
  ScheduledClassDayGroup(
    dayLabel: 'Today',
    classes: [
      ScheduledClass(
        id: 'c_001',
        name: 'Muay Thai',
        startTime: '6:00pm',
        endTime: '6:55pm',
        durationLabel: '55 min',
        instructorName: 'Andy Zerger',
        checkedInCount: 21,
        inSession: true,
        imageAsset: 'assets/images/class_muay_thai_session.png',
      ),
      ScheduledClass(
        id: 'c_002',
        name: 'BJJ NO-GI',
        startTime: '7:00pm',
        endTime: '7:55pm',
        durationLabel: '55 min',
        instructorName: 'Andy Zerger',
        attendingCount: 13,
        imageAsset: 'assets/images/class_bjj_nogi_today.png',
      ),
    ],
  ),
  ScheduledClassDayGroup(
    dayLabel: 'Wed 19',
    classes: [
      ScheduledClass(
        id: 'c_003',
        name: 'Muay Thai',
        startTime: '6:00pm',
        endTime: '6:55pm',
        durationLabel: '55 min',
        instructorName: 'Andy Zerger',
        attendingCount: 16,
        imageAsset: 'assets/images/class_muay_thai_wed.png',
      ),
      ScheduledClass(
        id: 'c_004',
        name: 'BJJ NO-GI',
        startTime: '7:00pm',
        endTime: '7:55pm',
        durationLabel: '55 min',
        instructorName: 'Andy Zerger',
        attendingCount: 11,
        imageAsset: 'assets/images/class_bjj_nogi_wed.png',
      ),
    ],
  ),
  ScheduledClassDayGroup(
    dayLabel: 'Thr 20',
    classes: [
      ScheduledClass(
        id: 'c_005',
        name: 'Muay Thai',
        startTime: '6:00pm',
        endTime: '6:55pm',
        durationLabel: '55 min',
        instructorName: 'Andy Zerger',
        imageAsset: 'assets/images/class_muay_thai_thu.png',
      ),
      ScheduledClass(
        id: 'c_006',
        name: 'BJJ NO-GI',
        startTime: '7:00pm',
        endTime: '7:55pm',
        durationLabel: '55 min',
        instructorName: 'Andy Zerger',
        imageAsset: 'assets/images/class_bjj_nogi_thu.png',
      ),
    ],
  ),
];
