class MockUpcomingSession {
  const MockUpcomingSession({
    required this.dayLabel,
    required this.time,
    required this.className,
    required this.mentor,
  });

  final String dayLabel;
  final String time;
  final String className;
  final String mentor;
}

const mockUpcomingSessions = <MockUpcomingSession>[
  MockUpcomingSession(
    dayLabel: 'Today',
    time: '12:00 pm',
    className: 'Muay Thai Class (55 min)',
    mentor: 'Andy Zerger',
  ),
  MockUpcomingSession(
    dayLabel: 'Wed 19',
    time: '7:00 pm',
    className: 'BJJ NO-GI (55 min)',
    mentor: 'Andy Zerger',
  ),
];

const mockStreakWeeks = 3;
