import 'package:mobile_app/customization/customization_service.dart';
import 'package:mobile_app/customization/data/customization_api_client.dart';
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
        ),
      );
    }

    final service = getIt<CustomizationService>();
    await service.initialize();
    CustomizationImagePrewarmer.prewarm(service);
  }
}
