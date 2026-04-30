import 'package:mobile_app/features/home/data/mock_class_schedule.dart';

/// Optional extra detail wrapper for the class booking screen. The base
/// [MockClass] (already used across the home schedule) is the primary
/// payload — this just holds the few extra fields the detail screen
/// renders that aren't on the schedule list item.
class MockClassDetail {
  const MockClassDetail({
    required this.classData,
    required this.location,
    required this.dateLabel,
    required this.description,
    required this.instructorName,
    required this.instructorBio,
    required this.instructorPfpAsset,
    required this.address,
    required this.mapAsset,
  });

  final MockClass classData;

  /// e.g. "Global MMA ‧ Dallas, TX".
  final String location;

  /// e.g. "Tue, Dec 18th".
  final String dateLabel;

  /// Long-form details body.
  final String description;

  /// Instructor display name (e.g. "Andy Zerger").
  final String instructorName;

  /// Long-form instructor bio.
  final String instructorBio;

  /// Local asset path for instructor headshot.
  final String instructorPfpAsset;

  /// Street address rendered under the map.
  final String address;

  /// Local asset path for the static map image.
  final String mapAsset;
}

const String _kInstructorAndy = 'assets/images/summary_instructor_andy.png';
const String _kMapAsset = 'assets/images/class_location_map.png';
const String _kAddress = '1336 Inwood Rd, Dallas, TX 75247';
const String _kAndyBio =
    'Andy Zerger, a prominent figure in MMA and Muay Thai. '
    'Developed fighters in the UFC, ESPN Boxing and more!';

const _muayThaiClass = MockClass(
  name: 'Muay Thai',
  timeRange: '6:00pm - 6:55pm CST',
  durationMinutes: 55,
  mentor: 'Coach Anan Chayanon',
  imageAsset: 'assets/images/class_muay_thai_today.png',
  attending: 21,
);

const mockMuayThaiDetail = MockClassDetail(
  classData: _muayThaiClass,
  location: 'Global MMA ‧ Dallas, TX',
  dateLabel: 'Tue, Dec 18th',
  description:
      'Sharpen your striking game with pad work, partner drills, and '
      'live technique rounds. All levels welcome — work at your '
      'pace, push your limits.',
  instructorName: 'Andy Zerger',
  instructorBio: _kAndyBio,
  instructorPfpAsset: _kInstructorAndy,
  address: _kAddress,
  mapAsset: _kMapAsset,
);

/// Lookup a detail entry for the given [MockClass] by name. Falls back to
/// a generic description so any class the home screen passes in still
/// renders correctly during the demo.
MockClassDetail detailFor(MockClass classData) {
  if (classData.name.toLowerCase().contains('muay')) {
    return MockClassDetail(
      classData: classData,
      location: 'Global MMA ‧ Dallas, TX',
      dateLabel: 'Tue, Dec 18th',
      description: mockMuayThaiDetail.description,
      instructorName: 'Andy Zerger',
      instructorBio: _kAndyBio,
      instructorPfpAsset: _kInstructorAndy,
      address: _kAddress,
      mapAsset: _kMapAsset,
    );
  }
  if (classData.name.toLowerCase().contains('bjj') ||
      classData.name.toLowerCase().contains('jiu')) {
    return MockClassDetail(
      classData: classData,
      location: 'Global MMA ‧ Dallas, TX',
      dateLabel: 'Wed, Dec 19th',
      description:
          'Drill fundamentals, work positional rounds, and finish with '
          'open rolling. Bring a clean gi — white belts welcome.',
      instructorName: 'Andy Zerger',
      instructorBio: _kAndyBio,
      instructorPfpAsset: _kInstructorAndy,
      address: _kAddress,
      mapAsset: _kMapAsset,
    );
  }
  return MockClassDetail(
    classData: classData,
    location: 'Global MMA ‧ Dallas, TX',
    dateLabel: 'This week',
    description:
        'Train alongside your team. Warm-up, technique work, and '
        'live rounds led by your coach.',
    instructorName: 'Andy Zerger',
    instructorBio: _kAndyBio,
    instructorPfpAsset: _kInstructorAndy,
    address: _kAddress,
    mapAsset: _kMapAsset,
  );
}
