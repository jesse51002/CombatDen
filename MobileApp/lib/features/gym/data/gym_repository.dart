import 'package:mobile_app/core/selected_gym.dart';
import 'package:mobile_app/core/video_service_config.dart';
import 'package:mobile_app/features/gym/data/gym_api_client.dart';
import 'package:mobile_app/features/gym/data/gym_detail.dart';

/// Single source of truth for the **selected gym's** detail (classes +
/// rewards), fetched by [selectedGym] gym id and cached per gym — so the home
/// schedule, class detail, and rewards screens share one load and switching
/// gym swaps it. Empty when no gym is selected yet.
///
/// Lazy app-wide singleton via [instance]. Mirrors `VideoFeedRepository`.
class GymRepository {
  GymRepository._();

  static final GymRepository instance = GymRepository._();

  final Map<String, Future<GymDetail>> _byGym = {};

  /// The selected gym's detail, fetched at most once per gym. On failure the
  /// cache entry is cleared and the error propagates so a rebuild can retry.
  Future<GymDetail> detail() {
    final gymId = selectedGym.gymId;
    if (gymId == null) {
      return Future.value(const GymDetail(classes: [], rewards: []));
    }
    return _byGym[gymId] ??= _fetch(gymId);
  }

  Future<GymDetail> _fetch(String gymId) async {
    final client = GymApiClient(baseUrl: kVideoBaseUrl, gymId: gymId);
    try {
      return await client.fetchDetail();
    } on GymFetchException {
      _byGym.remove(gymId);
      rethrow;
    }
  }
}
