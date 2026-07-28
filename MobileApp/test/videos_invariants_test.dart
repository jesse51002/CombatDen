import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/stub_asset_bundle.dart';
import 'helpers/video_fixtures.dart';

import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/features/videos/data/video.dart';
import 'package:mobile_app/features/videos/data/video_helpers.dart';
import 'package:mobile_app/features/videos/presentation/layouts/videos_layout_data.dart';
import 'package:mobile_app/features/videos/presentation/screens/videos_screen.dart';
import 'package:mobile_app/features/videos/presentation/widgets/featured_video_card.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_carousel_card.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_carousel_section.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_category_tabs.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_view_all_action.dart';
import 'package:mobile_app/features/videos/presentation/widgets/videos_feed_body.dart';
import 'package:mobile_app/features/videos/presentation/widgets/videos_feed_status.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';
import 'package:mobile_app/shared/widgets/video_recc_card/video_recc_card.dart';

/// The functional-equivalence gate for `videos_format`.
///
/// A layout format may change ARRANGEMENT ONLY. This asserts it
/// mechanically: every value of the enum is pumped over the same
/// fabricated feed and its element set is compared against the contract
/// below. A layout that drops the "view all" action, loses the featured
/// hero, hides a section, or shows fewer cards than the feed carries
/// fails here rather than in review.
///
/// The feed is fabricated, never fetched: `feedOverride` stands in for
/// the repository so nothing here touches the network.
void main() {
  /// Pump at a real phone size. At the default 800x600 test surface a
  /// cramped row still fits, so an arrangement that overflows on an
  /// actual device would pass unnoticed.
  void phoneSized(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Widget screen({
    required VideosFormat format,
    required Future<List<Video>> feed,
    String phase = 'only',
  }) {
    return withStubAssets(
      MaterialApp(
        home: VideosScreen(
          // The screen resolves its feed once, in `initState`. A test
          // that swaps feeds has to swap the State with it.
          key: ValueKey('${format.name}-$phase'),
          feedOverride: feed,
          formatOverride: format,
        ),
      ),
    );
  }

  /// The layout alone, over a payload the test owns, so the callbacks
  /// can be observed.
  Widget body({
    required VideosFormat format,
    required VideosLayoutData data,
  }) {
    return withStubAssets(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [VideosFeedBody(data: data, formatOverride: format)],
          ),
        ),
      ),
    );
  }

  Finder inFeatured(Type type) => find.descendant(
    of: find.byType(FeaturedVideoCard),
    matching: find.byType(type),
  );

  /// Every element the shipped screen renders, asserted against the
  /// fabricated [feed] that produced it.
  void expectFullElementSet(WidgetTester tester, VideoFeed feed) {
    // Shell.
    expect(find.byType(AppTopbar), findsOneWidget);
    expect(find.byType(AppBottomNavBar), findsOneWidget);

    // The top filter: All + one pill per big_group in the feed.
    expect(find.byType(VideoCategoryTabs), findsOneWidget);
    final tabs = tester.widget<VideoCategoryTabs>(
      find.byType(VideoCategoryTabs),
    );
    expect(tabs.tabs, ['All', ...feed.groups.map(displayLabel)]);
    expect(tabs.onTabSelected, isNotNull);
    for (final label in tabs.tabs) {
      expect(find.text(label), findsOneWidget);
    }

    // Exactly one featured hero, still carrying the shared recc card
    // and its Play action — and still the feed's top-relevance video.
    expect(find.byType(FeaturedVideoCard), findsOneWidget);
    expect(inFeatured(VideoReccCard), findsOneWidget);
    expect(inFeatured(AppPrimaryButton), findsOneWidget);
    expect(
      tester.widget<FeaturedVideoCard>(find.byType(FeaturedVideoCard)).video,
      feed.videos.first,
    );

    // One section per tag, each with its title and its view-all.
    expect(find.byType(VideoCarouselSection), findsNWidgets(feed.tags.length));
    for (final tag in feed.tags) {
      expect(find.text(displayLabel(tag)), findsOneWidget);
    }
    expect(find.byType(VideoViewAllAction), findsNWidgets(feed.tags.length));
    for (final action in tester.widgetList<VideoViewAllAction>(
      find.byType(VideoViewAllAction),
    )) {
      expect(action.onTap, isNotNull);
    }

    // A card for every video — no layout hides part of the feed.
    expect(
      find.byType(VideoCarouselCard),
      findsNWidgets(feed.videos.length),
    );
    for (final card in tester.widgetList<VideoCarouselCard>(
      find.byType(VideoCarouselCard),
    )) {
      expect(card.onTap, isNotNull);
    }

    // Loaded means no status: the feed is what is on screen.
    expect(find.byType(VideosFeedStatus), findsNothing);
  }

  group('every videos format carries the whole feed', () {
    final feed = videoFeed(tags: 3, groups: 2, perTag: 4);

    for (final format in VideosFormat.values) {
      testWidgets(format.name, (tester) async {
        phoneSized(tester);
        await tester.pumpWidget(
          screen(format: format, feed: Future.value(feed.videos)),
        );
        await tester.pump();

        expectFullElementSet(tester, feed);
      });
    }
  });

  group('a one-tag feed still renders every element', () {
    final feed = videoFeed(tags: 1, groups: 1, perTag: 2);

    for (final format in VideosFormat.values) {
      testWidgets(format.name, (tester) async {
        phoneSized(tester);
        await tester.pumpWidget(
          screen(format: format, feed: Future.value(feed.videos)),
        );
        await tester.pump();

        expectFullElementSet(tester, feed);
      });
    }
  });

  group('a fifteen-tag feed still renders every element', () {
    // The app owns no tag vocabulary: the count is the tenant's. A
    // layout that only works at three tags fails here.
    final feed = videoFeed(tags: 15, groups: 3, perTag: 2);

    for (final format in VideosFormat.values) {
      testWidgets(format.name, (tester) async {
        phoneSized(tester);
        await tester.pumpWidget(
          screen(format: format, feed: Future.value(feed.videos)),
        );
        await tester.pump();

        expectFullElementSet(tester, feed);
      });
    }
  });

  group('every videos format keeps loading, error and empty', () {
    for (final format in VideosFormat.values) {
      testWidgets(format.name, (tester) async {
        phoneSized(tester);

        // Loading: the request is still in flight.
        final pending = Completer<List<Video>>();
        await tester.pumpWidget(
          screen(format: format, feed: pending.future, phase: 'pending'),
        );
        expect(find.byType(VideosFeedStatus), findsOneWidget);
        expect(
          tester.widget<VideosFeedStatus>(find.byType(VideosFeedStatus)).kind,
          VideosFeedStatusKind.loading,
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Error: the request failed.
        pending.completeError(Exception('feed down'));
        await tester.pump();
        expect(find.byType(VideosFeedStatus), findsOneWidget);
        expect(find.text('Couldn\'t load videos right now.'), findsOneWidget);

        // Empty: the gym has no videos at all.
        await tester.pumpWidget(
          screen(
            format: format,
            feed: Future.value(const <Video>[]),
            phase: 'empty',
          ),
        );
        await tester.pump();
        expect(find.byType(VideosFeedStatus), findsOneWidget);
        expect(find.text('No videos yet.'), findsOneWidget);

        // The topbar and the nav frame every one of those states.
        expect(find.byType(AppTopbar), findsOneWidget);
        expect(find.byType(AppBottomNavBar), findsOneWidget);
      });
    }
  });

  group('every videos format keeps the empty-filter message', () {
    final feed = videoFeed(tags: 2, groups: 1, perTag: 2);

    for (final format in VideosFormat.values) {
      testWidgets(format.name, (tester) async {
        phoneSized(tester);
        await tester.pumpWidget(
          body(
            format: format,
            data: VideosLayoutData.fromFeed(
              videos: feed.videos,
              // A filter the feed carries nothing for.
              scope: 'nothing_here',
              onScopeSelected: (_) {},
              onVideoTap: (_) {},
              onViewAll: (_) {},
            ),
          ),
        );
        await tester.pump();

        // An unknown scope falls back to All, which is the shipped
        // behaviour — the filter never strands the member on a blank
        // screen.
        expect(find.byType(VideoCategoryTabs), findsOneWidget);
        expect(find.byType(FeaturedVideoCard), findsOneWidget);

        // The message itself is reachable from the same layouts.
        await tester.pumpWidget(
          body(
            format: format,
            data: VideosLayoutData.fromFeed(
              videos: const <Video>[],
              scope: null,
              onScopeSelected: (_) {},
              onVideoTap: (_) {},
              onViewAll: (_) {},
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(VideosFeedStatus), findsOneWidget);
        expect(find.text('Nothing here yet.'), findsOneWidget);
      });
    }
  });

  group('every videos format hands taps back with the same data', () {
    final feed = videoFeed(tags: 2, groups: 2, perTag: 3);

    for (final format in VideosFormat.values) {
      testWidgets(format.name, (tester) async {
        phoneSized(tester);
        final tapped = <Video>[];
        final viewedAll = <String>[];
        final scoped = <String?>[];

        await tester.pumpWidget(
          body(
            format: format,
            data: VideosLayoutData.fromFeed(
              videos: feed.videos,
              scope: null,
              onScopeSelected: scoped.add,
              onVideoTap: tapped.add,
              onViewAll: viewedAll.add,
            ),
          ),
        );
        await tester.pump();

        // Every card plays its own video.
        final cards = tester
            .widgetList<VideoCarouselCard>(find.byType(VideoCarouselCard))
            .toList();
        for (final card in cards) {
          card.onTap!();
        }
        expect(tapped.length, feed.videos.length);
        expect(tapped.toSet(), feed.videos.toSet());

        // Every section opens its own tag.
        for (final action in tester.widgetList<VideoViewAllAction>(
          find.byType(VideoViewAllAction),
        )) {
          action.onTap!();
        }
        expect(viewedAll, feed.tags);

        // The hero plays the featured video.
        tester
            .widget<FeaturedVideoCard>(find.byType(FeaturedVideoCard))
            .onTap!();
        expect(tapped.last, feed.videos.first);

        // Every pill re-filters.
        final tabs = tester.widget<VideoCategoryTabs>(
          find.byType(VideoCategoryTabs),
        );
        for (var i = 0; i < tabs.tabs.length; i++) {
          tabs.onTabSelected!(i);
        }
        expect(scoped, [null, ...feed.groups]);
      });
    }
  });

  group('the featured Play action is reachable', () {
    final feed = videoFeed(tags: 2, groups: 2, perTag: 2);

    for (final format in VideosFormat.values) {
      testWidgets(format.name, (tester) async {
        phoneSized(tester);
        var played = 0;

        await tester.pumpWidget(
          body(
            format: format,
            data: VideosLayoutData.fromFeed(
              videos: feed.videos,
              scope: null,
              onScopeSelected: (_) {},
              onVideoTap: (_) => played++,
              onViewAll: (_) {},
            ),
          ),
        );
        await tester.pump();

        final play = inFeatured(AppPrimaryButton);
        await tester.ensureVisible(play);
        await tester.pumpAndSettle();
        await tester.tap(play);
        expect(played, 1);
      });
    }
  });
}
