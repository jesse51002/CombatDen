import 'package:mobile_app/core/app_config.dart';
import 'package:mobile_app/core/video_service_config.dart';
import 'package:theme_flutter/customization_runtime.dart';
import 'package:mobile_app/features/videos/data/video.dart';
import 'package:mobile_app/features/videos/data/video_api_client.dart';

/// Single source of truth for the video feed of the **active theme**. The feed
/// is fetched by design id — the VideoService resolves the theme to its gym and
/// serves that gym's approved feed — so selecting a new theme in the picker
/// switches the feed with it. There is no app-side theme→feed table anymore.
///
/// Fetches each feed at most once and caches it per `designId`, so the home feed
/// and the post-class/post-booking recommendation surfaces share one load, and
/// switching back to a previously-seen theme is instant.
///
/// Lazy app-wide singleton via [instance] — there is no app-level service
/// locator, and the customization `getIt` is package-internal.
class VideoFeedRepository {
  VideoFeedRepository._();

  static final VideoFeedRepository instance = VideoFeedRepository._();

  final Map<String, Future<List<Video>>> _cacheByDesign = {};

  /// The live theme's design id (falls back to the build's default design
  /// before any switch in the picker).
  String get _activeDesignId =>
      ThemeRuntime.activeDesignId ?? AppConfig.designId;

  /// The active theme's feed, fetched at most once per `designId`. On failure
  /// the cache entry is cleared and the error propagates so a rebuild can retry.
  Future<List<Video>> feed() {
    final designId = _activeDesignId;
    return _cacheByDesign[designId] ??= _fetch(designId);
  }

  Future<List<Video>> _fetch(String designId) async {
    final client = VideoApiClient(
      baseUrl: kVideoBaseUrl,
      designId: designId,
    );
    try {
      return await client.fetchFeed();
    } on VideoFetchException {
      _cacheByDesign.remove(designId);
      rethrow;
    }
  }
}
