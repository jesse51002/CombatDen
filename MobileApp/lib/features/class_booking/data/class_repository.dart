import 'package:mobile_app/core/app_config.dart';
import 'package:mobile_app/core/app_styles.dart';
import 'package:customization_engine/customization_runtime.dart';
import 'package:mobile_app/features/class_booking/data/class_api_client.dart';
import 'package:mobile_app/features/class_booking/data/class_info.dart';

/// Single source of truth for the active style's four class cards. Paired with
/// the customization theme via [AppStyle] (same `videoAppId`/base URL as the
/// video feed); selecting a new style switches the classes too.
///
/// Fetches at most once per `videoAppId` and caches, so the home schedule and
/// the class detail screen share one load. Lazy app-wide singleton via
/// [instance]. Mirrors `VideoFeedRepository`.
class ClassRepository {
  ClassRepository._();

  static final ClassRepository instance = ClassRepository._();

  final Map<String, Future<List<ClassInfo>>> _cacheByVideoApp = {};

  AppStyle? get _activeStyle => appStyleForDesign(
    CustomizationRuntime.activeDesignId ?? AppConfig.designId,
  );

  /// Whether the active style has class cards. False → schedule shows empty.
  bool get hasClasses => _activeStyle != null;

  /// The active style's four class cards, fetched at most once per
  /// `videoAppId`. On failure the cache entry is cleared and the error
  /// propagates so a rebuild can retry.
  Future<List<ClassInfo>> classes() {
    final style = _activeStyle;
    if (style == null) return Future.value(const <ClassInfo>[]);
    return _cacheByVideoApp[style.videoAppId] ??= _fetch(style);
  }

  Future<List<ClassInfo>> _fetch(AppStyle style) async {
    final client = ClassApiClient(
      baseUrl: style.videoBaseUrl,
      videoAppId: style.videoAppId,
    );
    try {
      return await client.fetchClasses();
    } on ClassFetchException {
      _cacheByVideoApp.remove(style.videoAppId);
      rethrow;
    }
  }
}
