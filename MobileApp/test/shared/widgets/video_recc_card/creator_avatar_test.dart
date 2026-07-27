import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/video_recc_card/creator_avatar.dart';
import 'package:mobile_app/shared/widgets/video_recc_card/video_recc_card.dart';

/// A 1x1 transparent PNG — a real, decodable image so the "avatar present"
/// case renders without touching the network.
final Uint8List _kPixel = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

const double _kPfpSize = 55;

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _card({required ImageProvider? pfp}) => VideoReccCard(
      title: 'Guard retention drills',
      metaLabel: 'Combat Culture ‧ 168K views',
      thumbnail: MemoryImage(_kPixel),
      creatorPfp: pfp,
    );

void main() {
  group('creatorAvatarProvider', () {
    test('null url has no avatar', () {
      expect(creatorAvatarProvider(null), isNull);
    });

    test('empty url has no avatar (the live feed sends "")', () {
      expect(creatorAvatarProvider(''), isNull);
    });

    test('whitespace-only url has no avatar', () {
      expect(creatorAvatarProvider('   '), isNull);
    });

    test('a real url resolves to a provider', () {
      expect(creatorAvatarProvider('https://cdn.test/a.png'), isNotNull);
    });
  });

  group('VideoReccCard creator avatar', () {
    testWidgets('renders the avatar when a provider is given', (tester) async {
      await tester.pumpWidget(_host(_card(pfp: MemoryImage(_kPixel))));

      expect(find.byType(CreatorAvatar), findsOneWidget);
      expect(tester.getSize(find.byType(CreatorAvatar)).width, _kPfpSize);
    });

    testWidgets('omits the avatar entirely when there is none',
        (tester) async {
      await tester.pumpWidget(_host(_card(pfp: null)));

      expect(find.byType(CreatorAvatar), findsNothing);
      expect(find.text('Guard retention drills'), findsOneWidget);
    });

    testWidgets('leaves no gap behind when the avatar is omitted',
        (tester) async {
      await tester.pumpWidget(_host(_card(pfp: MemoryImage(_kPixel))));
      final withAvatar =
          tester.getTopLeft(find.text('Guard retention drills')).dx;

      await tester.pumpWidget(_host(_card(pfp: null)));
      final without = tester.getTopLeft(find.text('Guard retention drills')).dx;

      // The title reclaims exactly the avatar plus its one gap — no reserved
      // space, no double gap.
      expect(
        withAvatar - without,
        _kPfpSize + DesignConstants.spacingMedium,
      );
    });
  });
}
