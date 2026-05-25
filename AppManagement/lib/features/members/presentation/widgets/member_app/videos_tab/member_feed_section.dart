import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/video_api_client.dart';
import 'package:app_management/features/members/data/video_feed.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/videos_tab/video_format_helpers.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/videos_tab/video_tile.dart';
import 'package:app_management/shared/widgets/fill_grid.dart';
import 'package:app_management/shared/widgets/filter_pills.dart';
import 'package:app_management/shared/widgets/section_card.dart';
import 'package:app_management/shared/widgets/subtitle_section.dart';

/// The live member feed, pulled from the VideoService. Mirrors the member
/// app: a filter bar of fine-grained tags, "All" previewing each tag as a
/// single row (with a View all jump to that tag), and a selected tag
/// showing every video for it as a grid. The one screen that hits a real
/// backend, so the admin previews real thumbnails.
class MemberFeedSection extends StatefulWidget {
  const MemberFeedSection({super.key});

  @override
  State<MemberFeedSection> createState() => _MemberFeedSectionState();
}

class _MemberFeedSectionState extends State<MemberFeedSection> {
  late final Future<List<Video>> _future = VideoApiClient().fetchFeed();
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Automatically Curated Member Feed',
      child: FutureBuilder<List<Video>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _FeedMessage.loading();
          }
          if (snapshot.hasError) {
            return const _FeedMessage(
              'Could not reach the video service. Start it and reopen this '
              'tab to preview the live feed.',
            );
          }
          final videos = snapshot.data ?? const <Video>[];
          if (videos.isEmpty) {
            return const _FeedMessage('No videos in this feed yet.');
          }
          return _Feed(
            videos: videos,
            selectedIndex: _selectedIndex,
            onSelected: (i) => setState(() => _selectedIndex = i),
          );
        },
      ),
    );
  }
}

class _Feed extends StatelessWidget {
  final List<Video> videos;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _Feed({
    required this.videos,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tags = _orderedTags(videos);
    final index = selectedIndex.clamp(0, tags.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        FilterPills(
          labels: ['All', for (final t in tags) displayLabel(t)],
          selectedIndex: index,
          onSelected: onSelected,
        ),
        if (index == 0)
          _AllPreview(
            videos: videos,
            tags: tags,
            onViewAll: (tag) => onSelected(tags.indexOf(tag) + 1),
          )
        else
          _TagGrid(videos: _withTag(videos, tags[index - 1])),
      ],
    );
  }

  List<String> _orderedTags(List<Video> all) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final v in all) {
      for (final t in v.tags) {
        if (seen.add(t)) ordered.add(t);
      }
    }
    return ordered;
  }

  List<Video> _withTag(List<Video> all, String tag) =>
      all.where((v) => v.tags.contains(tag)).toList()
        ..sort((a, b) => a.relevanceIndex.compareTo(b.relevanceIndex));
}

/// "All": one non-scrolling preview row per tag (each video in exactly
/// one row, its first tag), capped to what fits. View all jumps to the
/// tag's full grid.
class _AllPreview extends StatelessWidget {
  final List<Video> videos;
  final List<String> tags;
  final ValueChanged<String> onViewAll;

  const _AllPreview({
    required this.videos,
    required this.tags,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final byFirstTag = <String, List<Video>>{};
    for (final v in videos) {
      if (v.tags.isEmpty) continue;
      byFirstTag.putIfAbsent(v.tags.first, () => []).add(v);
    }
    for (final list in byFirstTag.values) {
      list.sort((a, b) => a.relevanceIndex.compareTo(b.relevanceIndex));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        for (final tag in tags)
          if (byFirstTag[tag] != null)
            _TagPreviewRow(
              tag: tag,
              videos: byFirstTag[tag]!,
              onViewAll: () => onViewAll(tag),
            ),
      ],
    );
  }
}

class _TagPreviewRow extends StatelessWidget {
  final String tag;
  final List<Video> videos;
  final VoidCallback onViewAll;

  const _TagPreviewRow({
    required this.tag,
    required this.videos,
    required this.onViewAll,
  });

  static const double _kTileWidth = 280;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Row(
          children: [
            Expanded(child: Text(displayLabel(tag), style: DesignConstants.h3)),
            _ViewAllButton(onTap: onViewAll),
          ],
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = DesignConstants.spacingLarge;
            final fit = ((constraints.maxWidth + gap) / (_kTileWidth + gap))
                .floor()
                .clamp(1, videos.length);
            final shown = videos.take(fit).toList();
            // Stretch the shown tiles to fill the row width, no trailing gap.
            return FillGrid(
              columns: shown.length,
              children: [for (final v in shown) _tile(v)],
            );
          },
        ),
      ],
    );
  }
}

class _ViewAllButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ViewAllButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingTiny,
        children: [
          Text(
            'View all',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.primaryColor,
            ),
          ),
          Icon(
            Symbols.chevron_right_sharp,
            color: DesignConstants.primaryColor,
            weight: DesignConstants.iconWeight,
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _TagGrid extends StatelessWidget {
  final List<Video> videos;

  const _TagGrid({required this.videos});

  @override
  Widget build(BuildContext context) {
    return FillGrid(
      minItemWidth: 240,
      children: [for (final v in videos) _tile(v)],
    );
  }
}

Widget _tile(Video v) => VideoTile(
  thumbnail: NetworkImage(v.thumbnailUrl),
  avatar: NetworkImage(v.channelAvatarUrl),
  title: v.title,
  meta: v.metaLabel,
);

class _FeedMessage extends StatelessWidget {
  final String? message;

  const _FeedMessage(this.message);
  const _FeedMessage.loading() : message = null;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(
        child: message == null
            ? SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: DesignConstants.primaryColor,
                ),
              )
            : Text(
                message!,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}
