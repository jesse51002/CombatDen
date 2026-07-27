@Tags(['golden'])
library;

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
final Uint8List _kPixel = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
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

  for (final format in AppShellFormat.values) {
    testWidgets('shell preview: ${format.name}', (tester) async {
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
      await tester.pump(const Duration(milliseconds: 32));

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
