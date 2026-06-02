import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

/// Centralises the path prefix for the showcase's bundled fallback images.
/// They live in `app_management`'s own `assets/showcase/` (declared in this
/// app's pubspec), so they use the plain asset key — NOT a `packages/<pkg>/`
/// prefix, which only aliases assets from *dependency* packages, not the app's
/// own (these moved here from the `theme_flutter` package).
///
/// These are the showcase screens' bundled fallbacks (the same role
/// MobileApp's own bundled assets play for its real screens). The engine's
/// resolvers never own a fallback; the showcase widgets pass these in.
class ShowcaseAsset {
  ShowcaseAsset._();

  static const String _images = 'assets/showcase/';

  /// An [ImageProvider] for a packaged image, e.g. `streak_icon.png`.
  static ImageProvider image(String file) => AssetImage('$_images$file');

  /// An [ImageProvider] for injected gym content served as a network URL
  /// (reward / class photos). Disk-cached like the engine's brand images.
  static ImageProvider network(String url) => CachedNetworkImageProvider(url);

  /// Pick the right provider for showcase content: the injected gym [url] when
  /// present, otherwise the bundled [fallbackAsset]. Empty/null [url] falls back.
  static ImageProvider imageOrNetwork(String? url, String fallbackAsset) =>
      (url != null && url.isNotEmpty) ? network(url) : image(fallbackAsset);
}
