import 'package:mobile_app/features/home/data/mock_class_schedule.dart';

/// The non-API class-detail fields. The class's own content (name, image,
/// description, instructor) now comes from the live [MockClass]; this only
/// adds what the VideoService doesn't provide — location, date, address, and
/// the static map image.
class MockClassDetail {
  const MockClassDetail({
    required this.classData,
    required this.location,
    required this.dateLabel,
    required this.address,
    required this.mapAsset,
  });

  final MockClass classData;

  /// e.g. "Global MMA ‧ Dallas, TX".
  final String location;

  /// e.g. "This week".
  final String dateLabel;

  /// Street address rendered under the map.
  final String address;

  /// Local asset path for the static map image.
  final String mapAsset;
}

const String _kMapAsset = 'class_location_map.png';
const String _kAddress = '1336 Inwood Rd, Dallas, TX 75247';

/// Fallback class for when the detail screen is opened without a class
/// argument (defensive — the schedule always passes one).
const fallbackClass = MockClass(
  name: 'Class',
  timeRange: '6:00pm - 6:55pm',
  durationMinutes: 55,
  mentor: 'Coach',
  imageUrl: '',
  description: 'Train alongside your team.',
  instructorBio: '',
  instructorImageUrl: '',
  attending: 0,
);

/// Wraps a [MockClass] with the non-API location/map detail.
MockClassDetail detailFor(MockClass classData) => MockClassDetail(
  classData: classData,
  location: 'Global MMA ‧ Dallas, TX',
  dateLabel: 'This week',
  address: _kAddress,
  mapAsset: _kMapAsset,
);
