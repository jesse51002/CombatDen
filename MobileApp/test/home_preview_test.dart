@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/home_layout_host.dart';
import 'helpers/preview_fonts.dart';
import 'helpers/stub_asset_bundle.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/features/home/presentation/layouts/home_layout_body.dart';
import 'package:mobile_app/features/home/presentation/layouts/home_layout_data.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

/// Renders every `home_format` value to a PNG under `test/goldens/` so
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
/// Class images come from the network at runtime, which a test cannot
/// reach — they render as the same grey placeholder block the app falls
/// back to. The previews are for judging arrangement, not artwork.
/// A phone's WIDTH, but far more height than a phone has.
///
/// Home's header — topbar, upcoming-sessions card, schedule title — is
/// most of a real screen, so at 844pt every value's sheet would show the
/// same header and none of the schedule, which is the only thing that
/// differs between them. The width is what the arrangements actually
/// respond to, and it stays honest. The phone-height check belongs to
/// `home_invariants_test.dart`, which is where an overflow must fail.
void _reviewSized(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 2, 1500 * 2);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadPreviewFont);

  for (final format in HomeFormat.values) {
    testWidgets('home preview: ${format.name}', (tester) async {
      await runIgnoringFontFetchErrors(() async {
        _reviewSized(tester);
        stubImageCacheDirectory();

        await tester.pumpWidget(
          withStubAssets(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                backgroundColor: DesignConstants.backgroundColor,
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PreviewLabel(text: 'home_format = ${format.name}'),
                    Expanded(
                      child: AppScreenScaffold(
                        horizontalPadding: AppScreenHorizontalPadding.none,
                        bottomNav: const AppBottomNavBar(
                          selected: AppBottomNavTab.home,
                        ),
                        child: HomeLayoutBody(
                          formatOverride: format,
                          data: const HomeLayoutData(
                            classes: kTestClasses,
                            booked: true,
                          ),
                        ),
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

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/home_${format.name}.png'),
        );

        // The image cache manager schedules housekeeping timers the
        // first time a network image resolves. Let them fire, or the
        // binding fails the test for leaving a timer pending.
        await tester.pump(const Duration(seconds: 30));
      });
    });
  }
}

/// Which value the panel below is showing.
///
/// A bare [TextStyle] rather than a `DesignConstants` one, matching
/// `shell_preview_test.dart`: every app style resolves through
/// `google_fonts`, whose face a test cannot fetch, so app text renders as
/// solid blocks on these sheets. The label is the one string that has to
/// stay readable, so it uses the locally loaded default face instead.
class _PreviewLabel extends StatelessWidget {
  const _PreviewLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: DesignConstants.primaryColor,
      padding: EdgeInsets.all(DesignConstants.spacingSmall),
      child: Text(
        text,
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
