import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/features/profile/data/models/billing_rank.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_badge.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_section.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

BillingRank _rank({String? nextRankImageUrl}) => BillingRank(
      rankId: 'r1',
      name: 'Blue Belt',
      classesToNextMajor: 40,
      classesTillNextStep: 8,
      classesSinceRank: 4,
      imageUrl: 'https://cdn.test/blue.png',
      nextRankImageUrl: nextRankImageUrl,
    );

/// The provider backing the badge's belt [Image] (the badge holds exactly one).
ImageProvider _beltProvider(WidgetTester tester) {
  final image = tester.widget<Image>(
    find.descendant(of: find.byType(NextRankBadge), matching: find.byType(Image)),
  );
  return image.image;
}

void main() {
  group('NextRankBadge', () {
    testWidgets('renders the real next-rank art when a URL is present',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const NextRankBadge(
            badgeAsset: 'profile_next_rank_belt.png',
            progress: 0.5,
            imageUrl: 'https://cdn.test/purple.png',
          ),
        ),
      );

      final provider = _beltProvider(tester);
      expect(provider, isA<CachedNetworkImageProvider>());
      expect((provider as CachedNetworkImageProvider).url,
          'https://cdn.test/purple.png');
    });

    testWidgets('falls back to the themed/bundled belt when the URL is null',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const NextRankBadge(
            badgeAsset: 'profile_next_rank_belt.png',
            progress: 0.5,
          ),
        ),
      );

      expect(_beltProvider(tester), isNot(isA<CachedNetworkImageProvider>()));
    });

    testWidgets('falls back when the URL is an empty string', (tester) async {
      await tester.pumpWidget(
        _host(
          const NextRankBadge(
            badgeAsset: 'profile_next_rank_belt.png',
            progress: 0.5,
            imageUrl: '',
          ),
        ),
      );

      expect(_beltProvider(tester), isNot(isA<CachedNetworkImageProvider>()));
    });
  });

  group('NextRankSection', () {
    testWidgets('passes the payload next-rank image down to the badge',
        (tester) async {
      await tester.pumpWidget(
        _host(
          NextRankSection(
            rank: _rank(nextRankImageUrl: 'https://cdn.test/purple.png'),
          ),
        ),
      );

      expect(find.text('4 / 8 classes'), findsOneWidget);
      final provider = _beltProvider(tester);
      expect(provider, isA<CachedNetworkImageProvider>());
      expect((provider as CachedNetworkImageProvider).url,
          'https://cdn.test/purple.png');
    });

    testWidgets('degrades to the themed belt at the top of the ladder',
        (tester) async {
      await tester.pumpWidget(
        _host(NextRankSection(rank: _rank())),
      );

      expect(_beltProvider(tester), isNot(isA<CachedNetworkImageProvider>()));
    });
  });
}
