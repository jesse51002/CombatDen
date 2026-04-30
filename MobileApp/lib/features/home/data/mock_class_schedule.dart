class MockClass {
  const MockClass({
    required this.name,
    required this.timeRange,
    required this.durationMinutes,
    required this.mentor,
    required this.imageAsset,
    this.attending,
    this.isBooked = false,
  });

  final String name;
  final String timeRange;
  final int durationMinutes;
  final String mentor;
  final String imageAsset;
  final int? attending;
  final bool isBooked;
}

class MockDay {
  const MockDay({required this.label, required this.classes});

  final String label;
  final List<MockClass> classes;
}
