import 'package:flutter/foundation.dart';

import 'package:theme_flutter/customization_service.dart';
import 'package:theme_flutter/data/customization_api_client.dart';
import 'package:theme_flutter/data/models/customization_styles_page.dart';
import 'package:theme_flutter/service_locator.dart';

/// The one entry point the app needs. Call [initialize] once in
/// `main()` with the target app/design and the app's slot
/// manifest — DI wiring, the network fetch, and disk last-good
/// are all handled internally. The app never sees `get_it`, the
/// client, or the service.
///
/// App-agnostic: the only app-specific inputs are [appId] /
/// [designId] (from the app's `AppConfig`) and the expected slot
/// keys. The service URL and request path are package-internal.
/// (A URL-validation API key will be added here later; not
/// needed yet.)
///
/// Pass `livePreview: true` (the admin live-preview does) to bypass
/// the on-disk image cache and bust image URLs on every config
/// re-fetch, so an in-place asset edit shows up immediately. The
/// member app leaves it false.
class ThemeRuntime {
  // Private constructor to prevent instantiation
  ThemeRuntime._();

  static Future<void> initialize({
    required String appId,
    required String designId,
    required List<String> expectedColors,
    required List<String> expectedImages,
    required List<String> expectedFonts,
    required List<String> expectedText,
    required List<String> expectedIcons,
    bool livePreview = false,
  }) async {
    if (!getIt.isRegistered<ThemeService>()) {
      getIt.registerLazySingleton<ThemeApiClient>(
        () => ThemeApiClient(
          appId: appId,
          designId: designId,
        ),
      );
      getIt.registerSingleton<ThemeService>(
        ThemeService(
          getIt<ThemeApiClient>(),
          expectedColorKeys: expectedColors,
          expectedImageKeys: expectedImages,
          expectedFontKeys: expectedFonts,
          expectedTextKeys: expectedText,
          expectedIconKeys: expectedIcons,
          livePreview: livePreview,
        ),
      );
    }

    final service = getIt<ThemeService>();
    await service.initialize();
  }

  /// Whether the engine has been initialized (its [ThemeService] is
  /// registered). [changes], [activeDesignId], and [selectDesign] all throw
  /// until this is true, so a consumer that may build *before* the first
  /// [initialize] — e.g. an app-wide chrome widget that paints on screens
  /// other than the one that boots the engine — must guard on this before
  /// touching [changes].
  static bool get isReady => getIt.isRegistered<ThemeService>();

  /// Listenable that fires whenever the active customization changes
  /// (initial load + every [selectDesign]). Wrap the app root in a
  /// `ListenableBuilder` on this so the whole tree re-themes live.
  static Listenable get changes => getIt<ThemeService>();

  /// One page of the app's selectable styles. [query] is an optional
  /// case-insensitive substring filter on id or display name.
  static Future<ThemeStylesPage> fetchStylesPage({
    int offset = 0,
    int limit = 20,
    String? query,
  }) => getIt<ThemeService>().fetchStylesPage(
    offset: offset,
    limit: limit,
    query: query,
  );

  /// The design (preset/run) currently loaded, for marking the active
  /// style in a picker.
  static String? get activeDesignId =>
      getIt<ThemeService>().activeDesignId;

  /// The active design's human name (e.g. "Apex MMA") from the loaded
  /// customization — what to title a gym/brand surface with. Null until a
  /// design is loaded. Distinct from the app/brand name
  /// ([ThemeConfig.displayName]), which is stable across an app's designs.
  static String? get activeDesignName =>
      getIt<ThemeService>().current?.designName;

  /// Switches the live style. Returns whether the switch took
  /// effect. Never throws.
  static Future<bool> selectDesign(String designId) async {
    final service = getIt<ThemeService>();
    return service.selectDesign(designId);
  }
}
