import 'package:mobile_app/core/app_config.dart';
import 'package:mobile_app/core/app_styles.dart';
import 'package:mobile_app/customization/customization_runtime.dart';
import 'package:mobile_app/features/videos/data/video.dart';
import 'package:mobile_app/features/videos/data/video_api_client.dart';

/// Single source of truth for the video feed of the **active style**. The
/// feed is paired with the customization theme (see [AppStyle]); selecting a
/// new style in the picker switches both the theme and the feed.
///
/// Fetches each feed at most once and caches it per `videoAppId`, so the home
/// feed and the post-class/post-booking recommendation surfaces share one
/// load, and switching back to a previously-seen style is instant.
///
/// Lazy app-wide singleton via [instance] — there is no app-level service
/// locator, and the customization `getIt` is package-internal.
class VideoFeedRepository {
  VideoFeedRepository._();

  static final VideoFeedRepository instance = VideoFeedRepository._();

  final Map<String, Future<List<Video>>> _cacheByVideoApp = {};

  /// The curated style for the live theme (falls back to the build's default
  /// design before any switch). Null when the active design isn't one of ours.
  AppStyle? get _activeStyle => appStyleForDesign(
    CustomizationRuntime.activeDesignId ?? AppConfig.designId,
  );

  /// Whether the active style has a paired feed. False → the Videos tab shows
  /// an empty state instead of attempting a fetch.
  bool get hasVideos => _activeStyle != null;

  /// The active style's feed, fetched at most once per `videoAppId`. On
  /// failure the cache entry is cleared and the error propagates so a rebuild
  /// can retry.
  Future<List<Video>> feed() {
    final style = _activeStyle;
    if (style == null) return Future.value(const <Video>[]);
    return _cacheByVideoApp[style.videoAppId] ??= _fetch(style);
  }

  Future<List<Video>> _fetch(AppStyle style) async {
    final client = VideoApiClient(
      baseUrl: style.videoBaseUrl,
      videoAppId: style.videoAppId,
    );
    try {
      return await client.fetchFeed();
    } on VideoFetchException {
      _cacheByVideoApp.remove(style.videoAppId);
      rethrow;
    }
  }
}
