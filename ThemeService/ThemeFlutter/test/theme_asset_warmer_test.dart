import 'dart:typed_data';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:theme_flutter/data/models/color_mode.dart';
import 'package:theme_flutter/data/models/customization.dart';
import 'package:theme_flutter/theme/theme_asset_warmer.dart';

/// Stand-in for `ThemeService.resolveImageUrl`: absolutises relative slot
/// URLs, passes absolute ones through.
String _resolve(String raw) =>
    raw.startsWith('http') ? raw : 'http://host/$raw';

ThemeConfig _config({
  Map<String, String> images = const {},
  Map<String, String> icons = const {},
}) => ThemeConfig(
  app: 'a',
  displayName: 'A',
  designName: 'D',
  colorMode: ColorMode.dark,
  colors: const {},
  palette: const {},
  images: images,
  fonts: const {},
  texts: const {},
  icons: icons,
);

void main() {
  group('computeTargets', () {
    test('null config yields empty sets', () {
      final (images, icons) =
          ThemeAssetWarmer.computeTargets(null, _resolve);
      expect(images, isEmpty);
      expect(icons, isEmpty);
    });

    test('resolves relative URLs and keeps absolute ones', () {
      final (images, icons) = ThemeAssetWarmer.computeTargets(
        _config(
          images: {'bg': 'images/bg.png', 'logo': 'https://cdn/logo.png'},
          icons: {'nav': 'icons/nav.svg'},
        ),
        _resolve,
      );
      expect(images, {'http://host/images/bg.png', 'https://cdn/logo.png'});
      expect(icons, {'http://host/icons/nav.svg'});
    });

    test('dedupes URLs that resolve to the same target', () {
      final (images, _) = ThemeAssetWarmer.computeTargets(
        _config(images: {'a': 'images/x.png', 'b': 'images/x.png'}),
        _resolve,
      );
      expect(images, {'http://host/images/x.png'});
    });

    test('drops empty slot URLs', () {
      final (images, icons) = ThemeAssetWarmer.computeTargets(
        _config(
          images: {'a': 'images/x.png', 'b': ''},
          icons: {'i': '', 'j': 'icons/j.svg'},
        ),
        _resolve,
      );
      expect(images, {'http://host/images/x.png'});
      expect(icons, {'http://host/icons/j.svg'});
    });
  });

  group('flutter_svg cache evict-key round-trip', () {
    // The icon feature hinges on a freshly-reconstructed
    // `SvgNetworkLoader(url).cacheKey(null)` equalling the key the render
    // path / warm path inserted under. Prove insert-then-evict by an
    // independently-built key actually removes the entry.
    const url = 'http://host/icons/nav.svg';

    setUp(() => svg.cache.clear());
    tearDown(() => svg.cache.clear());

    test('evict(cacheKey(null)) removes what putIfAbsent(cacheKey(null)) added',
        () async {
      expect(svg.cache.count, 0);

      await svg.cache.putIfAbsent(
        SvgNetworkLoader(url).cacheKey(null),
        () async => ByteData(0),
      );
      expect(svg.cache.count, 1);

      // A different loader instance for the same URL must produce an equal key.
      final removed =
          svg.cache.evict(SvgNetworkLoader(url).cacheKey(null));
      expect(removed, isTrue);
      expect(svg.cache.count, 0);
    });

    test('a different URL key does not collide', () async {
      await svg.cache.putIfAbsent(
        SvgNetworkLoader(url).cacheKey(null),
        () async => ByteData(0),
      );
      final removed = svg.cache.evict(
        SvgNetworkLoader('http://host/icons/other.svg').cacheKey(null),
      );
      expect(removed, isFalse);
      expect(svg.cache.count, 1);
    });
  });
}
