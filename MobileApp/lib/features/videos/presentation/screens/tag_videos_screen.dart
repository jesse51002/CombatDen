import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/data/video.dart';
import 'package:mobile_app/features/videos/data/video_feed_repository.dart';
import 'package:mobile_app/features/videos/data/video_helpers.dart';
import 'package:mobile_app/features/videos/data/video_selectors.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';
import 'package:mobile_app/shared/widgets/video_recc_card/video_recc_card.dart';

/// The "view all" destination for a carousel: a scrollable vertical list of
/// every video carrying one specific tag, in backend (relevancy) order.
/// Independent of the home page's top filter. Reached via
/// `AppRoutes.videoTagList` with the tag string as the route argument.
class TagVideosScreen extends StatelessWidget {
  const TagVideosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final arg = ModalRoute.of(context)?.settings.arguments;
    final tag = arg is String ? arg : '';

    return AppScreenScaffold(
      bottomNav: const AppBottomNavBar(selected: AppBottomNavTab.videos),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          _Header(title: displayLabel(tag)),
          Expanded(child: _TagList(tag: tag)),
        ],
      ),
    );
  }
}

class _TagList extends StatelessWidget {
  const _TagList({required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Video>>(
      future: VideoFeedRepository.instance.feed(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final videos = sortByRelevance(
          (snapshot.data ?? const <Video>[]).where((v) => v.tags.contains(tag)),
        );
        if (snapshot.hasError || videos.isEmpty) {
          return Center(
            child: Text(
              'No videos here yet.',
              style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
            ),
          );
        }
        return SingleChildScrollView(
          padding: EdgeInsets.only(bottom: DesignConstants.spacingBig),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingBig,
            children: [
              for (final video in videos)
                VideoReccCard(
                  title: video.title,
                  metaLabel: video.metaLabel,
                  thumbnail: CachedNetworkImageProvider(video.thumbnailUrl),
                  creatorPfp: CachedNetworkImageProvider(
                    video.channelAvatarUrl,
                  ),
                  // Real playback is a follow-up; no-op for now.
                  onTap: () => debugPrint('TODO: play ${video.url}'),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: Icon(
            Symbols.chevron_left_sharp,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.text,
            size: DesignConstants.iconSize2xl,
          ),
        ),
        Expanded(child: Text(title, style: DesignConstants.h1)),
      ],
    );
  }
}
