import 'package:theme_flutter/customization_service.dart';
import 'package:theme_flutter/data/customization_api_client.dart';
import 'package:theme_flutter/data/models/color_mode.dart';
import 'package:theme_flutter/data/models/customization.dart';
import 'package:theme_flutter/service_locator.dart';

/// A [ThemeService] whose loaded customization is set by hand.
///
/// The real service only ever loads over the network or from
/// `SharedPreferences`, neither of which belongs in a resolution test.
/// This overrides the one getter the format resolver reads through
/// (`current.texts`), and — because [ThemeService] is a
/// `ChangeNotifier` — [load] is a genuine theme-change notification on
/// the real listenable type, not a stand-in for one.
class StubThemeService extends ThemeService {
  StubThemeService([Map<String, String> texts = const {}])
    : _texts = Map.of(texts),
      super(
        ThemeApiClient(appId: 'test', designId: 'test'),
        expectedColorKeys: const [],
        expectedImageKeys: const [],
        expectedFontKeys: const [],
        expectedTextKeys: const [],
        expectedIconKeys: const [],
      );

  Map<String, String> _texts;

  /// Swap the tenant's slots and fire the change, exactly as loading a
  /// new design does.
  void load(Map<String, String> texts) {
    _texts = Map.of(texts);
    notifyListeners();
  }

  @override
  ThemeConfig? get current => ThemeConfig(
    app: 'test',
    displayName: 'Test',
    designName: 'Test',
    colorMode: ColorMode.dark,
    colors: const {},
    palette: const {},
    images: const {},
    fonts: const {},
    texts: _texts,
    icons: const {},
  );
}

/// Register [service] as the loaded engine for the duration of a test.
/// Call the returned function to tear it back down.
void Function() installStubTheme(StubThemeService service) {
  if (getIt.isRegistered<ThemeService>()) {
    getIt.unregister<ThemeService>();
  }
  getIt.registerSingleton<ThemeService>(service);
  return () {
    if (getIt.isRegistered<ThemeService>()) {
      getIt.unregister<ThemeService>();
    }
  };
}
