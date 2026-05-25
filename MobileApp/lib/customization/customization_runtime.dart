import 'package:flutter/foundation.dart';

import 'package:mobile_app/customization/customization_service.dart';
import 'package:mobile_app/customization/data/customization_api_client.dart';
import 'package:mobile_app/customization/data/models/customization_style.dart';
import 'package:mobile_app/customization/image_prewarmer.dart';
import 'package:mobile_app/customization/service_locator.dart';

/// The one entry point the app needs. Call [initialize] once in
/// `main()` with the target app/design and the app's slot
/// manifest — DI wiring, the network fetch, disk last-good, and
/// image cache pre-warming are all handled internally. The app
/// never sees `get_it`, the client, or the service.
///
/// App-agnostic: the only app-specific inputs are [appId] /
/// [designId] (from the app's `AppConfig`) and the expected slot
/// keys. The service URL and request path are package-internal.
/// (A URL-validation API key will be added here later; not
/// needed yet.)
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
    required List<String> expectedLotties,
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
          expectedLottieKeys: expectedLotties,
        ),
      );
    }

    final service = getIt<CustomizationService>();
    await service.initialize();
    CustomizationImagePrewarmer.prewarm(service);
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

  /// Switches the live style and re-warms its image cache. Returns
  /// whether the switch took effect. Never throws.
  static Future<bool> selectDesign(String designId) async {
    final service = getIt<CustomizationService>();
    final ok = await service.selectDesign(designId);
    if (ok) {
      CustomizationImagePrewarmer.prewarm(service);
    }
    return ok;
  }
}
