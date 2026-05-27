import 'package:flutter/foundation.dart';

import 'package:customization_engine/customization_service.dart';
import 'package:customization_engine/data/customization_api_client.dart';
import 'package:customization_engine/data/models/customization_style.dart';
import 'package:customization_engine/service_locator.dart';

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
class CustomizationRuntime {
  // Private constructor to prevent instantiation
  CustomizationRuntime._();

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
    if (!getIt.isRegistered<CustomizationService>()) {
      getIt.registerLazySingleton<CustomizationApiClient>(
        () => CustomizationApiClient(
          appId: appId,
          designId: designId,
        ),
      );
      getIt.registerSingleton<CustomizationService>(
        CustomizationService(
          getIt<CustomizationApiClient>(),
          expectedColorKeys: expectedColors,
          expectedImageKeys: expectedImages,
          expectedFontKeys: expectedFonts,
          expectedTextKeys: expectedText,
          expectedIconKeys: expectedIcons,
          livePreview: livePreview,
        ),
      );
    }

    final service = getIt<CustomizationService>();
    await service.initialize();
  }

  /// Listenable that fires whenever the active customization changes
  /// (initial load + every [selectDesign]). Wrap the app root in a
  /// `ListenableBuilder` on this so the whole tree re-themes live.
  static Listenable get changes => getIt<CustomizationService>();

  /// The app's selectable styles (design name + celebration image).
  static Future<List<CustomizationStyle>> fetchStyles() =>
      getIt<CustomizationService>().fetchStyles();

  /// The design (preset/run) currently loaded, for marking the active
  /// style in a picker.
  static String? get activeDesignId =>
      getIt<CustomizationService>().activeDesignId;

  /// Switches the live style. Returns whether the switch took
  /// effect. Never throws.
  static Future<bool> selectDesign(String designId) async {
    final service = getIt<CustomizationService>();
    return service.selectDesign(designId);
  }
}
