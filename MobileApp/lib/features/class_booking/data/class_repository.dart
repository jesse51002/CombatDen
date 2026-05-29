import 'package:mobile_app/features/class_booking/data/class_info.dart';
import 'package:mobile_app/features/gym/data/gym_repository.dart';

/// The gym's branded class cards. A thin view over [GymRepository]: the gym's
/// classes + rewards arrive together in one `GET /gyms/{gymId}` fetch, so the
/// home schedule and the class detail screen share that single cached load.
/// Lazy app-wide singleton via [instance].
class ClassRepository {
  ClassRepository._();

  static final ClassRepository instance = ClassRepository._();

  /// The gym's class cards, from the shared (cached) gym detail.
  Future<List<ClassInfo>> classes() =>
      GymRepository.instance.detail().then((detail) => detail.classes);
}
