@Tags(['golden'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

/// Renders every `app_shell_format` value to a PNG under
/// `test/goldens/` so the arrangements can be reviewed side by side
/// without booting an emulator.
///
/// Regenerate with:
///   flutter test --tags golden --update-goldens --run-skipped
///
/// These are review artefacts, not assertions about pixels: they are
/// tagged `golden` so a normal `flutter test` run skips them and a
/// font or platform difference can never redden CI.
/// An 8x8 grey square served for every asset key, so an image slot
/// reads as a visible placeholder block rather than a hole. The
/// previews are for judging arrangement, not artwork.
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

/// Swallows the platform noise the real-async window lets through.
///
/// Letting the frame advance for real (the [WidgetTester.runAsync]
/// below, which is what makes the bundled images decode) also lets
/// `google_fonts` reach for Jura. The test binding answers every HTTP
/// request with a 400, so it fails — as a dangling future, whose error
/// lands in the ambient zone and fails the test AFTER the golden has
/// already been written. Guarding the pump keeps it in a zone of its
/// own.
///
/// This does NOT hide layout errors: an overflow is reported through
/// `FlutterError.onError`, not through the zone, so it still reddens
/// the test.
void _ignorePlatformNoise(Object error, StackTrace stack) {}

void main() {
  setUpAll(_loadFont);

  for (final format in AppShellFormat.values) {
    testWidgets('shell preview: ${format.name}', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await runZonedGuarded(() async {
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
                        'app_shell_format = ${format.name}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: DesignConstants.primaryButtonText,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    AppTopbar(
                      formatOverride: format,
                      mode: AppTopbarMode.bigLogo,
                      showBackButton: false,
                      gymName: 'Global MMA',
                      logoAsset: 'logo_primary.png',
                      streakDays: 12,
                      pointsLabel: '2,480',
                      rankBadgeAsset: 'rank_belt.png',
                    ),
                    const Expanded(
                      child: SingleChildScrollView(child: _BodyStandIn()),
                    ),
                    AppBottomNavBar(
                      formatOverride: format,
                      selected: AppBottomNavTab.home,
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
      }, _ignorePlatformNoise);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/shell_${format.name}.png'),
      );
    });
  }
}

/// Neutral filler standing in for whichever screen the shell frames, so
/// the previews compare chrome rather than content.
class _BodyStandIn extends StatelessWidget {
  const _BodyStandIn();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(DesignConstants.screenHorizontalPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          for (var i = 0; i < 6; i++)
            Container(
              height: 46,
              decoration: BoxDecoration(
                color: DesignConstants.card,
                borderRadius: BorderRadius.circular(
                  DesignConstants.radiusSmall,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
