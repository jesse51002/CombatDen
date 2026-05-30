import 'package:mobile_app/features/class_booking/data/class_info.dart';
import 'package:mobile_app/features/rewards/data/reward.dart';

/// This build's whole gym content, fetched once from the VideoService
/// (`GET /gyms/{gymId}` → `GymDetail`) and held in [GymRepository] memory: the
/// branded [classes] and the points-store [rewards]. The video feed is fetched
/// separately (it pages). The served `specification` is admin-only, so the
/// member app ignores it.
class GymDetail {
  const GymDetail({required this.classes, required this.rewards});

  final List<ClassInfo> classes;
  final List<Reward> rewards;

  factory GymDetail.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(Object? raw, T Function(Map<String, dynamic>) build) =>
        raw is List
        ? raw
              .whereType<Map>()
              .map((e) => build(Map<String, dynamic>.from(e)))
              .toList(growable: false)
        : const [];
    return GymDetail(
      classes: list(json['classes'], ClassInfo.fromJson),
      rewards: list(json['rewards'], Reward.fromJson),
    );
  }
}
