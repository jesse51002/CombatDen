import 'package:flutter/widgets.dart';

/// Centralises the `packages/<pkg>/...` prefix every consumer must use to
/// reach an asset declared in THIS package's pubspec. Declaring the assets
/// in `customization_engine`'s `flutter.assets` ships them automatically
/// with any app that depends on the package — no re-declaration needed in
/// the consuming app's pubspec.
///
/// These are the showcase screens' bundled fallbacks (the same role
/// MobileApp's own bundled assets play for its real screens). The engine's
/// resolvers never own a fallback; the showcase widgets pass these in.
class ShowcaseAsset {
  ShowcaseAsset._();

  static const String _images = 'packages/customization_engine/assets/images/';

  /// An [ImageProvider] for a packaged image, e.g. `streak_icon.png`.
  static ImageProvider image(String file) => AssetImage('$_images$file');
}
