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
import 'package:mobile_app/features/rewards/data/reward.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_layout.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_layout_data.dart';

/// Renders every `rewards_format` value to a PNG under `test/goldens/`
/// so the arrangements can be reviewed side by side without booting an
/// emulator.
///
/// Regenerate with:
///   flutter test --tags golden --update-goldens --run-skipped
///
/// These are review artefacts, not assertions about pixels: they are
/// tagged `golden` so a normal `flutter test` run skips them and a font
/// or platform difference can never redden CI.
///
/// Reward images are network URLs, so they resolve to the card-coloured
/// error block here — the previews are for judging arrangement, not
/// artwork. The stub bundle covers the BUNDLED assets (logo, rank badge)
/// with a grey square so those slots read as placeholders, not holes.

/// The reward images are NETWORK images, so `cached_network_image`
/// spins up its disk cache the moment one resolves — and its first move
/// is a `path_provider` platform call that no test host answers. Left
/// alone that lands as an unhandled async error the moment the preview
/// gives the image futures real time to run, which is exactly what the
/// preview has to do. Answering the channel with a scratch directory
/// lets the cache manager get as far as the (mocked, offline) fetch,
/// whose failure the image's own `errorBuilder` already handles.
void _stubPathProvider() {
  final scratch = Directory.systemTemp.createTempSync('rewards_preview');
  addTearDown(() => scratch.deleteSync(recursive: true));
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => scratch.path,
      );
}

/// Every text style in this app resolves through `google_fonts`, which
/// fetches the family over HTTP the first time it is asked for — and
/// flutter_test answers every HTTP request with a 400. google_fonts
/// rethrows that failure out of a future nobody listens to, so it lands
/// as an unhandled async error and reddens the test the instant the
/// golden comparison gives real async time.
///
/// The preview does not need that fetch to SUCCEED: [_loadFont] already
/// registers a face under the family google_fonts falls back to. It only
/// needs it never to FAIL. So font requests hang here and every other
/// request fails fast, which is what a reward's network image wants
/// anyway — a fast failure paints its card-coloured placeholder.
class _OfflineHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _OfflineHttpClient();
}

class _OfflineHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    if (url.host == 'fonts.gstatic.com') {
      return Completer<HttpClientRequest>().future;
    }
    return Future<HttpClientRequest>.error(
      const SocketException('offline under flutter_test'),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A real typeface so the previews show words rather than tofu boxes.
Future<void> _loadFont() async {
  const path =
      '/usr/share/fonts/liberation-sans-fonts/LiberationSans-Regular.ttf';
  final file = File(path);
  if (!file.existsSync()) return;
  final bytes = await file.readAsBytes();
  for (final family in ['Jura', 'Roboto']) {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

const _rewards = <Reward>[
  Reward(
    title: 'Free Week',
    imageUrl: 'https://example.test/free-week.png',
    priceLabel: 'Free',
    pointsCost: 800,
  ),
  Reward(
    title: 'Limited edition championship rash guard with the gym '
        'crest embroidered across both shoulders',
    imageUrl: 'https://example.test/rash-guard.png',
    priceLabel: '30% off',
    pointsCost: 1200,
  ),
  Reward(
    title: 'Private Coaching Hour',
    imageUrl: 'https://example.test/private.png',
    priceLabel: 'Free',
    pointsCost: 3400,
  ),
  Reward(
    title: 'Gym Duffel Bag',
    imageUrl: 'https://example.test/duffel.png',
    priceLabel: '50% off',
    pointsCost: 6800,
  ),
  Reward(
    title: 'Annual Membership',
    imageUrl: 'https://example.test/annual.png',
    priceLabel: 'Free',
    pointsCost: 20000,
  ),
];

const _data = RewardsLayoutData(
  gymName: 'Global MMA',
  logoAsset: 'gym_logo_global_mma.png',
  streakDays: 3,
  pointsLabel: '3.4k',
  rankBadgeAsset: 'icon_rank_belt.png',
  totalPoints: 3400,
  rewards: _rewards,
);

void main() {
  setUpAll(_loadFont);

  final previousOverrides = HttpOverrides.current;
  setUp(() => HttpOverrides.global = _OfflineHttpOverrides());
  tearDown(() => HttpOverrides.global = previousOverrides);

  for (final format in RewardsFormat.values) {
    testWidgets('rewards preview: ${format.name}', (tester) async {
      _stubPathProvider();
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        withStubAssets(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: DesignConstants.backgroundColor,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Label(format: format),
                  Expanded(
                    child: RewardsLayout(
                      data: _data,
                      formatOverride: format,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      // Deliberately NO `runAsync` here, unlike the shell preview. This
      // screen holds network images, so real async time wakes
      // `cached_network_image`'s cache store, which queues a 10s
      // cleanup timer that outlives the tree and trips flutter_test's
      // pending-timer assertion. Fake time is enough: the pumps carry
      // the points headline past its reveal window, and the reward
      // images paint their placeholder either way. The cost is that
      // BUNDLED bitmaps (the topbar logo and rank badge) stay blank —
      // shell chrome, already reviewed in the shell previews.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/rewards_${format.name}.png'),
      );
    });
  }
}

/// Names the panel so a sheet of previews is readable side by side.
class _Label extends StatelessWidget {
  const _Label({required this.format});

  final RewardsFormat format;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: DesignConstants.primaryColor,
      padding: EdgeInsets.all(DesignConstants.spacingSmall),
      child: Text(
        'rewards_format = ${format.name}',
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
