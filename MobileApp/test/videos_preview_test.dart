@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/video_fixtures.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/features/videos/presentation/screens/videos_screen.dart';

/// Renders every `videos_format` value to a PNG under `test/goldens/`
/// so the arrangements can be reviewed side by side without booting an
/// emulator or a backend.
///
/// Regenerate with:
///   flutter test --tags golden --update-goldens --run-skipped
///
/// These are review artefacts, not assertions about pixels: they are
/// tagged `golden` so a normal `flutter test` run skips them and a font
/// or platform difference can never redden CI.
///
/// An 8x8 grey square is served for every asset key, and the feed's
/// thumbnails are unreachable URLs, so every image slot reads as a
/// placeholder block rather than a hole. The previews are for judging
/// arrangement, not artwork.
final Uint8List _kPixel = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x08,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x4B, 0x6D, 0x29, 0xDC, 0x00, 0x00, 0x00,
  0x15, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xEC, 0x9E, 0x30, 0x8D,
  0x01, 0x1B, 0x60, 0x62, 0xC0, 0x01, 0x06, 0xA7, 0x04, 0x00, 0x55, 0xF2,
  0x01, 0xC1, 0x9C, 0x7D, 0xA5, 0x80, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _StubAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin' || key == 'AssetManifest.bin.json') {
      return const StandardMessageCodec().encodeMessage(<String, Object>{})!;
    }
    return ByteData.sublistView(_kPixel);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async => '';
}

/// A real typeface so the previews show words rather than tofu boxes.
Future<void> _loadFont() async {
  const path = '/usr/share/fonts/liberation-sans-fonts/'
      'LiberationSans-Regular.ttf';
  final file = File(path);
  if (!file.existsSync()) return;
  final bytes = await file.readAsBytes();
  for (final family in ['Jura', 'Roboto']) {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFont);

  final feed = videoFeed(tags: 3, groups: 2, perTag: 3);

  for (final format in VideosFormat.values) {
    testWidgets('videos preview: ${format.name}', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: _StubAssetBundle(),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: DesignConstants.backgroundColor,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: double.infinity,
                    color: DesignConstants.primaryColor,
                    padding: EdgeInsets.all(DesignConstants.spacingSmall),
                    child: Text(
                      'videos_format = ${format.name}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: DesignConstants.primaryButtonText,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: VideosScreen(
                      feedOverride: Future.value(feed.videos),
                      formatOverride: format,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      // Asset decode is async: let the image futures complete, then
      // pump so the decoded frames are actually painted.
      await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 50),
      ));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/videos_${format.name}.png'),
      );
    });
  }
}
