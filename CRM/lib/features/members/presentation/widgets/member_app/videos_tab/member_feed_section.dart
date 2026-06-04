import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/members/data/video_api_client.dart';
import 'package:crm/features/members/data/video_feed.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/video_format_helpers.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/video_tile.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/video_wrap_grid.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/view_all_button.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/your_videos_grid.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/your_videos_row.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/horizontal_scroller.dart';
import 'package:crm/shared/widgets/section_card.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';
import 'package:crm/shared/widgets/filter_pills.dart';

// Page size for a genre's paginated "View all" grid.
const int _kPageSize = 24;

/// The member feed for the selected gym. Pills switch sections: "All" shows a
/// scrollable preview row per section ("Your videos" first, then each live
/// genre), and selecting a section opens its full View all grid. "Your videos"
/// is the gym's own uploads (mock); the genres pull live from the VideoService
/// — the one screen that hits a real backend, so the admin previews real
/// thumbnails.
class MemberFeedSection extends StatefulWidget {
  const MemberFeedSection({super.key});

  @override
  State<MemberFeedSection> createState() => _MemberFeedSectionState();
}

class _MemberFeedSectionState extends State<MemberFeedSection> {
  // Genres discovered once per (gym, feed) and cached, so switching gyms or
  // toggling rejected swaps the sections and revisiting is instant. The
  // rejected feed has its own genres, hence the feed flag in the key.
  final Map<String, Future<List<FeedSection>>> _previewByKey = {};
  int _selectedIndex = 0;
  bool _showRejected = false;

  // One request powers the whole "All" view — each genre sampled server-side,
  // so there's no per-genre request storm. Cached per (gym, feed) so switching
  // gyms or toggling rejected swaps the sections and revisiting is instant.
  Future<List<FeedSection>> _previewFor(String gymId, bool rejected) =>
      _previewByKey['$gymId-$rejected'] ??= VideoApiClient(
        gymId: gymId,
      ).fetchPreview(rejected: rejected);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: selectedGym,
      builder: (context, _) {
        final gymId = selectedGym.videoGymId;
        if (gymId == null) {
          return const SubtitleSection(
            title: 'Member feed',
            child: _FeedMessage(
              'Select a gym in the Theme tab to preview its feed.',
            ),
          );
        }
        return SubtitleSection(
          title: 'Member feed',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            // Tuck the toggle right above the pills so it's easy to find.
            spacing: DesignConstants.spacingMedium,
            children: [
              _RejectedToggle(
                value: _showRejected,
                // Switching feeds resets to "All": the approved and rejected
                // feeds have different pills.
                onChanged: (v) => setState(() {
                  _showRejected = v;
                  _selectedIndex = 0;
                }),
              ),
              // Your videos (mock) shows only in the approved feed; the genres
              // degrade to a loading/error/empty message without hiding the
              // rest of the feed.
              FutureBuilder<List<FeedSection>>(
                future: _previewFor(gymId, _showRejected),
                builder: (context, snapshot) {
                  return _Feed(
                    gymId: gymId,
                    sections: snapshot.data ?? const <FeedSection>[],
                    rejected: _showRejected,
                    genresLoading:
                        snapshot.connectionState != ConnectionState.done,
                    genresErrored: snapshot.hasError,
                    selectedIndex: _selectedIndex,
                    onSelected: (i) => setState(() => _selectedIndex = i),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The compact switch under the "Member feed" title that flips the whole feed
/// between the approved videos and the scan's rejected list — same pills, rows,
/// and View all, just the rejected data with a "Keep this video" action.
class _RejectedToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _RejectedToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text('Show rejected videos', style: DesignConstants.h3),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _Feed extends StatelessWidget {
  final String gymId;
  final List<FeedSection> sections;
  final bool rejected;
  final bool genresLoading;
  final bool genresErrored;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _Feed({
    required this.gymId,
    required this.sections,
    required this.rejected,
    required this.genresLoading,
    required this.genresErrored,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    // Pills: [All] [Your videos] [genre…]. "Your videos" (the gym's own
    // uploads) only belongs to the approved feed — the rejected feed is purely
    // the scan's discards — so it drops out when rejected is on.
    final showYourVideos = !rejected;
    final tags = [for (final s in sections) s.tag];
    final labels = [
      'All',
      if (showYourVideos) 'Your videos',
      for (final t in tags) displayLabel(t),
    ];
    final genreOffset = showYourVideos ? 2 : 1;
    final index = selectedIndex.clamp(0, labels.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        FilterPills(
          labels: labels,
          selectedIndex: index,
          onSelected: onSelected,
        ),
        if (index == 0)
          _AllSections(
            gymId: gymId,
            sections: sections,
            rejected: rejected,
            genresLoading: genresLoading,
            genresErrored: genresErrored,
            onSelected: onSelected,
          )
        else if (showYourVideos && index == 1)
          YourVideosGrid(
            detail: selectedGym.detail,
            gymName: selectedGym.displayName,
          )
        else
          _TagPager(
            key: ValueKey('$gymId-$rejected-${tags[index - genreOffset]}'),
            gymId: gymId,
            tag: tags[index - genreOffset],
            rejected: rejected,
          ),
      ],
    );
  }
}

/// "All": the Your videos preview row first (approved feed only), then one
/// preview row per live genre. The genres degrade to a loading/error/empty
/// message in place, so Your videos stays visible regardless of the service.
class _AllSections extends StatelessWidget {
  final String gymId;
  final List<FeedSection> sections;
  final bool rejected;
  final bool genresLoading;
  final bool genresErrored;
  final ValueChanged<int> onSelected;

  const _AllSections({
    required this.gymId,
    required this.sections,
    required this.rejected,
    required this.genresLoading,
    required this.genresErrored,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        if (!rejected)
          YourVideosRow(
            onViewAll: () => onSelected(1),
            detail: selectedGym.detail,
            gymName: selectedGym.displayName,
          ),
        _genres(),
      ],
    );
  }

  Widget _genres() {
    if (genresLoading) return const _InlineLoading();
    if (genresErrored) {
      return const _FeedMessage(
        'Could not reach the video service. Start it and reopen this tab to '
        'preview the live feed.',
      );
    }
    if (sections.isEmpty) {
      return _FeedMessage(
        rejected
            ? 'No rejected videos for this gym.'
            : 'No videos in this feed yet.',
      );
    }
    final genreOffset = rejected ? 1 : 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        for (var i = 0; i < sections.length; i++)
          _PreviewRow(
            section: sections[i],
            rejected: rejected,
            onViewAll: () => onSelected(i + genreOffset),
          ),
      ],
    );
  }
}

/// One genre's preview row: a header with a "View all" jump and a scrollable
/// strip of the videos the one-shot preview already returned for this genre.
/// No request of its own — that's the whole point of the batched preview.
class _PreviewRow extends StatelessWidget {
  final FeedSection section;
  final bool rejected;
  final VoidCallback onViewAll;

  const _PreviewRow({
    required this.section,
    required this.rejected,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    if (section.videos.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(displayLabel(section.tag), style: DesignConstants.h3),
            ),
            ViewAllButton(onTap: onViewAll),
          ],
        ),
        HorizontalScroller(
          children: [
            for (final v in section.videos) _tile(v, rejected: rejected),
          ],
        ),
      ],
    );
  }
}

/// A genre's full feed: paginated grid of fixed-width tiles + a "Load more"
/// that pulls the next page (`offset`) until the genre's total is reached.
class _TagPager extends StatefulWidget {
  final String gymId;
  final String tag;
  final bool rejected;

  const _TagPager({
    super.key,
    required this.gymId,
    required this.tag,
    required this.rejected,
  });

  @override
  State<_TagPager> createState() => _TagPagerState();
}

class _TagPagerState extends State<_TagPager> {
  final List<Video> _videos = [];
  int _total = 0;
  bool _loading = false;
  bool _errored = false;
  bool _loadedFirst = false;

  bool get _hasMore => _videos.length < _total;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _errored = false;
    });
    try {
      final page = await VideoApiClient(gymId: widget.gymId).fetchFeed(
        videoType: widget.tag,
        rejected: widget.rejected,
        limit: _kPageSize,
        offset: _videos.length,
      );
      if (!mounted) return;
      setState(() {
        _videos.addAll(page.videos);
        _total = page.total;
        _loadedFirst = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errored = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loadedFirst) {
      if (_errored) {
        return const _FeedMessage(
          'Could not reach the video service. Start it and reopen this tab '
          'to preview the live feed.',
        );
      }
      return const _FeedMessage.loading();
    }
    if (_videos.isEmpty) {
      return _FeedMessage(
        widget.rejected
            ? 'No rejected videos in this genre yet.'
            : 'No videos in this genre yet.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        VideoWrapGrid(
          tiles: [for (final v in _videos) _tile(v, rejected: widget.rejected)],
        ),
        if (_hasMore)
          Center(
            child: AppOutlineButton(
              text: _loading ? 'Loading…' : 'Load more',
              onPressed: _loading ? null : _loadMore,
            ),
          ),
      ],
    );
  }
}

Widget _tile(Video v, {bool rejected = false}) => VideoTile(
  thumbnail: NetworkImage(v.thumbnailUrl),
  avatar: NetworkImage(v.channelAvatarUrl),
  title: v.title,
  meta: v.metaLabel,
  rejected: rejected,
);

/// A small inline spinner for a section that's still loading (no card chrome).
class _InlineLoading extends StatelessWidget {
  const _InlineLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(child: AppSpinner()),
    );
  }
}

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
            ? const AppSpinner()
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
