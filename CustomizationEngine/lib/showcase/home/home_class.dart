/// Clone of MobileApp's `MockClass` / `MockDay` (home schedule models) for
/// the showcase. The real screen's class content comes from a live
/// VideoService fetch; here it's bundled const dummy data instead. The
/// `imageAsset` is a bundled png filename (resolved via `ShowcaseAsset`) —
/// the real app uses a network `imageUrl`, but the showcase is offline.
class ShowcaseClass {
  const ShowcaseClass({
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

  /// Instructor display name.
  final String mentor;

  /// Bundled class-photo filename (resolved via `ShowcaseAsset.image`).
  final String imageAsset;

  final int? attending;
  final bool isBooked;
}

class ShowcaseDay {
  const ShowcaseDay({required this.label, required this.classes});

  final String label;
  final List<ShowcaseClass> classes;
}

/// The four daily classes, mirroring the VideoService's four-class feed. The
/// schedule generator loops these into the fixed time slots, one per slot.
const List<ShowcaseClass> showcaseClasses = [
  ShowcaseClass(
    name: 'Fundamentals',
    timeRange: '9:00am - 9:55am',
    durationMinutes: 55,
    mentor: 'Coach Marcus Reyes',
    imageAsset: 'class_photo_1.png',
  ),
  ShowcaseClass(
    name: 'Striking & Pads',
    timeRange: '11:00am - 11:55am',
    durationMinutes: 55,
    mentor: 'Coach Dana Whitfield',
    imageAsset: 'class_photo_2.png',
  ),
  ShowcaseClass(
    name: 'Open Mat Sparring',
    timeRange: '6:00pm - 6:55pm',
    durationMinutes: 55,
    mentor: 'Coach Leo Tanaka',
    imageAsset: 'class_photo_3.png',
  ),
  ShowcaseClass(
    name: 'Conditioning',
    timeRange: '7:00pm - 7:55pm',
    durationMinutes: 55,
    mentor: 'Coach Priya Nair',
    imageAsset: 'class_photo_4.png',
  ),
];
