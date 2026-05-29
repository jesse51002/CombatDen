import 'package:mobile_app/core/app_config.dart';
import 'package:mobile_app/core/video_service_config.dart';
import 'package:theme_flutter/customization_runtime.dart';
import 'package:mobile_app/features/class_booking/data/class_api_client.dart';
import 'package:mobile_app/features/class_booking/data/class_info.dart';

/// Single source of truth for the active theme's four class cards. Fetched by
/// design id — the VideoService resolves the theme to its gym and serves that
/// gym's class cards — so selecting a new theme switches the classes too.
///
/// Fetches at most once per `designId` and caches, so the home schedule and the
/// class detail screen share one load. Lazy app-wide singleton via [instance].
/// Mirrors `VideoFeedRepository`.
class ClassRepository {
  ClassRepository._();

  static final ClassRepository instance = ClassRepository._();

  final Map<String, Future<List<ClassInfo>>> _cacheByDesign = {};

  /// The live theme's design id (falls back to the build's default design
  /// before any switch in the picker).
  String get _activeDesignId =>
      ThemeRuntime.activeDesignId ?? AppConfig.designId;

  /// The active theme's four class cards, fetched at most once per `designId`.
  /// On failure the cache entry is cleared and the error propagates so a
  /// rebuild can retry.
  Future<List<ClassInfo>> classes() {
    final designId = _activeDesignId;
    return _cacheByDesign[designId] ??= _fetch(designId);
  }

  Future<List<ClassInfo>> _fetch(String designId) async {
    final client = ClassApiClient(
      baseUrl: kVideoBaseUrl,
      designId: designId,
    );
    try {
      return await client.fetchClasses();
    } on ClassFetchException {
      _cacheByDesign.remove(designId);
      rethrow;
    }
  }
}
