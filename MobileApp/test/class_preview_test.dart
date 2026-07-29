@Tags(['golden'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/stub_asset_bundle.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/features/class_booking/presentation/screens/class_screen.dart';
import 'package:mobile_app/features/home/data/mock_class_schedule.dart';

/// Renders every `class_format` value to a PNG under `test/goldens/` so
/// the arrangements can be reviewed side by side without booting an
/// emulator.
///
/// Regenerate with:
///   flutter test --tags golden --update-goldens --run-skipped
///
/// These are review artefacts, not assertions about pixels: they are
/// tagged `golden` so a normal `flutter test` run skips them and a font
/// or platform difference can never redden CI.
///
/// The class photo, the coach headshot and the map are network images
/// in the real app, so they render as their error placeholder here —
/// a flat card-coloured block in the shape and position the layout
/// gives them, which is what a preview of an ARRANGEMENT needs. The
/// `FMT` tab on the right edge is the debug-only format picker handle
/// that every screen carries in a debug build.
const MockClass _sample = MockClass(
  name: 'Muay Thai Sparring',
  timeRange: '6:00pm - 6:55pm',
  durationMinutes: 55,
  mentor: 'Coach Ana',
  imageUrl: 'https://example.test/class.jpg',
  description:
      'Six rounds on the pads, then live rounds with the team. Bring '
      'shin guards and a mouthpiece; wraps are available at the desk.',
  instructorBio:
      'Ten years cornering fighters at the national level, and the coach '
      'who runs the gym\'s competition team.',
  instructorImageUrl: 'https://example.test/coach.jpg',
  attending: 12,
);

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
/// below, which is what makes the bundled images decode) also lets two
/// plugin-backed futures run: `google_fonts` reaching for Jura, and
/// `cached_network_image` asking `path_provider` for a cache directory.
/// The test binding answers every HTTP request with a 400 and there is
/// no plugin behind that channel, so both fail — as dangling futures,
/// whose errors land in the ambient zone and fail the test AFTER the
/// golden has already been written. Guarding the pump keeps them in a
/// zone of their own.
///
/// This does NOT hide layout errors: an overflow is reported through
/// `FlutterError.onError`, not through the zone, so it still reddens
/// the test.
void _ignorePlatformNoise(Object error, StackTrace stack) {}

void main() {
  setUpAll(_loadFont);

  for (final format in ClassFormat.values) {
    testWidgets('class preview: ${format.name}', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await runZonedGuarded(() async {
        await tester.pumpWidget(
          withStubAssets(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                backgroundColor: DesignConstants.backgroundColor,
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PanelLabel(format: format),
                    Expanded(
                      child: ClassScreen(
                        formatOverride: format,
                        classData: _sample,
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
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 32));
        }
      }, _ignorePlatformNoise);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/class_${format.name}.png'),
      );
    });
  }
}

class _PanelLabel extends StatelessWidget {
  const _PanelLabel({required this.format});

  final ClassFormat format;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: DesignConstants.primaryColor,
      padding: EdgeInsets.all(DesignConstants.spacingSmall),
      child: Text(
        'class_format = ${format.name}',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: DesignConstants.primaryButtonText,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
