import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/data/models/gym_video_card.dart';
import 'package:mobile_app/features/videos/presentation/widgets/gym_video_carousel_card.dart';
import 'package:mobile_app/shared/widgets/video_recc_card/creator_avatar.dart';

const double _kPfpSize = 35;

GymVideoCard _card({required String channelAvatarUrl}) => GymVideoCard(
      videoId: 'v1',
      url: 'https://youtu.be/v1',
      title: 'Guard retention drills',
      thumbnailUrl: 'https://cdn.test/thumb.jpg',
      channelName: 'Combat Culture',
      channelUrl: 'https://youtube.com/@combat',
      channelAvatarUrl: channelAvatarUrl,
      relevanceIndex: 0,
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('GymVideoCarouselCard creator avatar', () {
    testWidgets('omits the avatar when channel_avatar_url is empty',
        (tester) async {
      await tester.pumpWidget(
        _host(GymVideoCarouselCard(card: _card(channelAvatarUrl: ''))),
      );

      expect(find.byType(CreatorAvatar), findsNothing);
      expect(find.text('Guard retention drills'), findsOneWidget);
    });

    testWidgets('renders the avatar when channel_avatar_url is present',
        (tester) async {
      await tester.pumpWidget(
        _host(
          GymVideoCarouselCard(
            card: _card(channelAvatarUrl: 'https://cdn.test/a.png'),
          ),
        ),
      );

      expect(find.byType(CreatorAvatar), findsOneWidget);
      expect(tester.getSize(find.byType(CreatorAvatar)).width, _kPfpSize);
    });

    testWidgets('the title closes up over the omitted avatar', (tester) async {
      await tester.pumpWidget(
        _host(
          GymVideoCarouselCard(
            card: _card(channelAvatarUrl: 'https://cdn.test/a.png'),
          ),
        ),
      );
      final withAvatar =
          tester.getTopLeft(find.text('Guard retention drills')).dx;

      await tester.pumpWidget(
        _host(GymVideoCarouselCard(card: _card(channelAvatarUrl: ''))),
      );
      final without = tester.getTopLeft(find.text('Guard retention drills')).dx;

      expect(
        withAvatar - without,
        _kPfpSize + DesignConstants.spacingMedium,
      );
    });
  });
}
