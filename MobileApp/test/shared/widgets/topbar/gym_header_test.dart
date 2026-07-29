import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/shared/widgets/topbar/gym_header.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _header({String? gymLogoUrl}) => GymHeader(
      gymName: 'Titan Dojo',
      logoAsset: 'gym_logo_global_mma.png',
      gymLogoUrl: gymLogoUrl,
    );

/// The provider backing the logo [Image] — the header's only image, above the
/// gym name.
ImageProvider _logoProvider(WidgetTester tester) => tester
    .widget<Image>(
      find
          .descendant(of: find.byType(GymHeader), matching: find.byType(Image))
          .first,
    )
    .image;

void main() {
  group('GymHeader logo', () {
    testWidgets("renders the gym's OWN uploaded logo when it has one",
        (tester) async {
      await tester.pumpWidget(
        _host(_header(gymLogoUrl: 'https://cdn.test/titan.png')),
      );

      final provider = _logoProvider(tester);
      expect(provider, isA<CachedNetworkImageProvider>());
      expect(
        (provider as CachedNetworkImageProvider).url,
        'https://cdn.test/titan.png',
      );
    });

    testWidgets('falls back to the themed mark when the gym has no logo',
        (tester) async {
      await tester.pumpWidget(_host(_header()));

      expect(_logoProvider(tester), isNot(isA<CachedNetworkImageProvider>()));
    });

    testWidgets('treats a blank URL as no logo, not as a broken one',
        (tester) async {
      await tester.pumpWidget(_host(_header(gymLogoUrl: '   ')));

      expect(_logoProvider(tester), isNot(isA<CachedNetworkImageProvider>()));
    });

    testWidgets(
        'a failed load falls back to the themed mark rather than a hole',
        (tester) async {
      await tester.pumpWidget(
        _host(_header(gymLogoUrl: 'https://cdn.test/gone.png')),
      );

      final image = tester.widget<Image>(
        find
            .descendant(of: find.byType(GymHeader), matching: find.byType(Image))
            .first,
      );
      expect(image.errorBuilder, isNotNull);

      // The builder's output is what a 404 actually paints: a themed logo at
      // the same box, never an empty gap.
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => image.errorBuilder!(
              context,
              Exception('404'),
              StackTrace.empty,
            ),
          ),
        ),
      );
      final fallback = tester.widget<Image>(find.byType(Image).first);
      expect(fallback.image, isNot(isA<CachedNetworkImageProvider>()));
      expect(fallback.width, 100);
      expect(fallback.height, 100);
    });

    testWidgets('always shows the gym name alongside the mark', (tester) async {
      await tester.pumpWidget(
        _host(_header(gymLogoUrl: 'https://cdn.test/titan.png')),
      );

      expect(find.text('Titan Dojo'), findsOneWidget);
    });
  });
}
