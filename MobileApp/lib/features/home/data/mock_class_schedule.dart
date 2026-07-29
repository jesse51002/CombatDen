/// A class in the schedule. Its content (name, image, instructor, description)
/// comes from the live VideoService class cards; the time slot, duration, and
/// the demo-only attending/booked flags are assigned by the schedule generator.
class MockClass {
  const MockClass({
    required this.name,
    required this.timeRange,
    required this.durationMinutes,
    required this.mentor,
    required this.imageUrl,
    required this.description,
    required this.instructorBio,
    required this.instructorImageUrl,
    this.attending,
    this.isBooked = false,
  });

  final String name;
  final String timeRange;
  final int durationMinutes;

  /// Instructor display name (from the class card's `instructor_name`).
  final String mentor;

  /// Network URLs from the VideoService class card.
  final String imageUrl;
  final String description;
  final String instructorBio;
  final String instructorImageUrl;

  final int? attending;
  final bool isBooked;
}

class MockDay {
  const MockDay({required this.label, required this.classes});

  final String label;
  final List<MockClass> classes;
}
