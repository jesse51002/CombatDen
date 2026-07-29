import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rank_header.dart';
import 'package:mobile_app/shared/widgets/rank/rank_belt_image.dart';

Widget _host({String? imageUrl, String? sub}) => MaterialApp(
      home: Scaffold(
        body: RankHeader(
          imageUrl: imageUrl,
          rankTitle: 'Blue Belt',
          rankSubtitle: sub,
        ),
      ),
    );

void main() {
  group('the profile belt follows the app\'s ONE belt rule', () {
    testWidgets('it resolves through the shared RankBeltImage', (tester) async {
      // The profile used to skip the themed `rank_belt` rung and fall straight
      // to the bundled asset, so a tenant that customised its belt saw the
      // custom art in the topbar and the celebration cards but NOT on the rank
      // screen. All four sites share one widget now; this is the guard.
      await tester.pumpWidget(_host());

      expect(find.byType(RankBeltImage), findsOneWidget);
    });

    testWidgets('the member\'s own art still wins', (tester) async {
      await tester.pumpWidget(_host(imageUrl: 'https://cdn.test/blue.png'));

      final image = tester.widget<Image>(
        find.descendant(
          of: find.byType(RankBeltImage),
          matching: find.byType(Image),
        ),
      );
      expect(image.image, isA<CachedNetworkImageProvider>());
      expect(
        (image.image as CachedNetworkImageProvider).url,
        'https://cdn.test/blue.png',
      );
    });

    testWidgets('no art falls back, and the belt keeps its 77 x 50 box',
        (tester) async {
      await tester.pumpWidget(_host());

      final image = tester.widget<Image>(
        find.descendant(
          of: find.byType(RankBeltImage),
          matching: find.byType(Image),
        ),
      );
      expect(image.image, isNot(isA<CachedNetworkImageProvider>()));
      // The shared widget carries no size of its own — the site boxes it.
      final size = tester.getSize(find.byType(RankBeltImage));
      expect(size.width, closeTo(77, 0.01));
      expect(size.height, closeTo(50, 0.01));
    });

    testWidgets('a blank sub-label is omitted, not printed as a blank line',
        (tester) async {
      await tester.pumpWidget(_host(sub: ''));
      expect(find.text(''), findsNothing);

      await tester.pumpWidget(_host(sub: '2 Stripes'));
      expect(find.text('2 Stripes'), findsOneWidget);
    });
  });
}
