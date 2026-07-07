import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/members/data/gym_content_repository.dart';
import 'package:crm/features/members/data/video_api_client.dart';
import 'package:crm/features/members/data/video_feed.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/video_curation_dialog.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/video_format_helpers.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/video_tile.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/video_wrap_grid.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/view_all_button.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/your_video_tile.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/your_videos_feed.dart';
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
/// is the gym's own real, editable feed (add a YouTube link / remove); the
/// genres are that same feed grouped by genre. Both pull live from the backend,
/// and every tile opens its watch page in a new tab.
class MemberFeedSection extends StatefulWidget {
  const MemberFeedSection({super.key});

  @override
  State<MemberFeedSection> createState() => _MemberFeedSectionState();
}

class _MemberFeedSectionState extends State<MemberFeedSection> {
  // The "All" preview sections held as RESOLVED state (not a Future), per
  // (gym, feed) key — so a removal mutates the list synchronously and the row
  // updates in place, with no FutureBuilder re-entering its loading state. The
  // rejected feed has its own genres, hence the feed flag in the key.
  final Map<String, List<FeedSection>> _sectionsByKey = {};
  final Set<String> _loadingKeys = {};
  final Set<String> _erroredKeys = {};
  int _selectedIndex = 0;
  bool _showRejected = false;

  // The cache key for the current (gym, feed): one shared key in admin (the
  // authed real-gym preview), per-(slug, rejected) in the public browser.
  String _keyFor(String gymId, bool rejected) {
    final adminGymId = selectedGym.gymId;
    return adminGymId != null
        ? '$adminGymId-admin-$rejected'
        : '$gymId-$rejected';
  }

  // Load the preview once per key (each genre sampled server-side, so one
  // request powers the whole "All" view). Admin → authed real-gym endpoint;
  // public browser → the unauthenticated template path. Safe to call in build:
  // it no-ops once loaded/loading and only setStates from the async callback.
  void _ensureLoaded(String gymId, bool rejected) {
    final key = _keyFor(gymId, rejected);
    if (_sectionsByKey.containsKey(key) ||
        _loadingKeys.contains(key) ||
        _erroredKeys.contains(key)) {
      return;
    }
    _loadingKeys.add(key);
    _erroredKeys.remove(key);
    final adminGymId = selectedGym.gymId;
    final future = adminGymId != null
        ? GymContentRepository(
            ApiClient(),
          ).fetchVideoPreview(adminGymId, rejected: rejected)
        : VideoApiClient(gymId: gymId).fetchPreview(rejected: rejected);
    future
        .then((sections) {
          if (!mounted) return;
          setState(() {
            _sectionsByKey[key] = sections;
            _loadingKeys.remove(key);
          });
        })
        .catchError((_) {
          if (!mounted) return;
          setState(() {
            _loadingKeys.remove(key);
            _erroredKeys.add(key);
          });
        });
  }

  /// Remove a queried video from the "All" preview, then drop it from the held
  /// sections synchronously — the row updates in place, no refetch/flicker.
  Future<void> _removePreviewVideo(Video video) async {
    final key = _keyFor(selectedGym.videoGymId ?? '', _showRejected);
    // Rejected view → "Keep" (un-reject); else reject (with why).
    final ok = _showRejected
        ? await keepGenreVideo(context, video)
        : await confirmAndRemoveGenreVideo(context, video);
    if (ok && mounted) {
      final sections = _sectionsByKey[key];
      if (sections == null) return;
      setState(() {
        _sectionsByKey[key] = [
          for (final s in sections)
            FeedSection(
              tag: s.tag,
              videos: s.videos.where((x) => x.videoId != video.videoId).toList(),
            ),
        ];
      });
    }
  }

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
        // The rejected toggle is meaningful in both contexts now: the real-gym
        // feed has a scan_status rejected list (admin can Keep videos back), and
        // the template path has the scan's rejected list.
        final isAdmin = selectedGym.gymId != null;
        final showRejected = _showRejected;
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
              // Load the preview into held state (no-op once cached); the genres
              // degrade to a loading/error/empty message without hiding the rest
              // of the feed. A removal mutates the held sections in place.
              Builder(
                builder: (context) {
                  _ensureLoaded(gymId, showRejected);
                  final key = _keyFor(gymId, showRejected);
                  return _Feed(
                    gymId: gymId,
                    sections: _sectionsByKey[key] ?? const <FeedSection>[],
                    rejected: showRejected,
                    genresLoading: _loadingKeys.contains(key),
                    genresErrored: _erroredKeys.contains(key),
                    selectedIndex: _selectedIndex,
                    onSelected: (i) => setState(() => _selectedIndex = i),
                    // Real removes (with a logged "why") only in the admin feed.
                    onPreviewRemove: isAdmin ? _removePreviewVideo : null,
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
  // Preview-row remove (admin only; updates the cached sections). The grid
  // builds its own local-removal handler off the same admin gate.
  final void Function(Video)? onPreviewRemove;

  const _Feed({
    required this.gymId,
    required this.sections,
    required this.rejected,
    required this.genresLoading,
    required this.genresErrored,
    required this.selectedIndex,
    required this.onSelected,
    required this.onPreviewRemove,
  });

  @override
  Widget build(BuildContext context) {
    // Pills: [All] [Your videos] [genre…]. "Your videos" is the gym's own
    // editable feed, so it only shows in the admin context (a real gym is
    // selected) and never in the rejected feed (the scan's discards). The
    // public theme browser has no owner feed, so it drops out there.
    final showYourVideos = !rejected && selectedGym.gymId != null;
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
            showYourVideos: showYourVideos,
            genresLoading: genresLoading,
            genresErrored: genresErrored,
            onSelected: onSelected,
            onRemove: onPreviewRemove,
          )
        else if (showYourVideos && index == 1)
          YourVideosFeed.full(gymId: selectedGym.gymId!)
        else
          _TagPager(
            key: ValueKey('$gymId-$rejected-${tags[index - genreOffset]}'),
            gymId: gymId,
            tag: tags[index - genreOffset],
            rejected: rejected,
            // The grid drops removed tiles locally; removal is admin-only.
            enableRemove: onPreviewRemove != null,
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
  final bool showYourVideos;
  final bool genresLoading;
  final bool genresErrored;
  final ValueChanged<int> onSelected;
  final void Function(Video)? onRemove;

  const _AllSections({
    required this.gymId,
    required this.sections,
    required this.rejected,
    required this.showYourVideos,
    required this.genresLoading,
    required this.genresErrored,
    required this.onSelected,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        if (showYourVideos)
          YourVideosFeed.preview(
            gymId: selectedGym.gymId!,
            onViewAll: () => onSelected(1),
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
      if (rejected) {
        return const _FeedMessage('No rejected videos for this gym.');
      }
      // A gym with real spec criteria has queued work the worker fulfils
      // within 24h, so an empty feed reads as "on the way", not "none".
      final detail = selectedGym.detail;
      final hasSpec = detail?.spec.videosDesc.isNotEmpty == true ||
          detail?.spec.avoidDesc.isNotEmpty == true;
      return _FeedMessage(
        hasSpec
            ? 'Your videos are on the way. New videos can take up to '
              '24 hours to appear.'
            : 'No videos in this feed yet.',
        icon: hasSpec ? Symbols.schedule_sharp : null,
      );
    }
    // Pills are [All] [Your videos?] [genre…]; the genre rows start after All
    // (+ Your videos when shown), so View all jumps to i + this offset.
    final genreOffset = showYourVideos ? 2 : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        for (var i = 0; i < sections.length; i++)
          _PreviewRow(
            section: sections[i],
            rejected: rejected,
            onViewAll: () => onSelected(i + genreOffset),
            onRemove: onRemove,
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
  final void Function(Video)? onRemove;

  const _PreviewRow({
    required this.section,
    required this.rejected,
    required this.onViewAll,
    required this.onRemove,
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
            for (final v in section.videos)
              _tile(v, rejected: rejected, onRemove: onRemove),
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
  final bool enableRemove;

  const _TagPager({
    super.key,
    required this.gymId,
    required this.tag,
    required this.rejected,
    required this.enableRemove,
  });

  @override
  State<_TagPager> createState() => _TagPagerState();
}

class _TagPagerState extends State<_TagPager> {
  final List<Video> _videos = [];
  int _total = 0;
  // DB-row cursor: tracks how many rows the backend has consumed, NOT how many
  // videos were rendered. The backend may skip rows that fail validation, so
  // _videos.length can be less than the DB rows consumed — using _videos.length
  // as the next offset would re-fetch already-seen rows and produce duplicates.
  int _dbOffset = 0;
  bool _loading = false;
  bool _errored = false;
  bool _loadedFirst = false;

  bool get _hasMore => _dbOffset < _total;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  /// Remove a queried video, then drop it from this grid locally — no refetch.
  // In the rejected view the tile action is "Keep" (un-reject); otherwise it's
  // the reject (with "why"). Either way drop the tile from this grid locally.
  Future<void> _remove(Video video) async {
    final ok = widget.rejected
        ? await keepGenreVideo(context, video)
        : await confirmAndRemoveGenreVideo(context, video);
    if (ok && mounted) {
      setState(() {
        _videos.removeWhere((x) => x.videoId == video.videoId);
        if (_total > 0) _total -= 1;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _errored = false;
    });
    try {
      final VideoPage page;
      final adminGymId = selectedGym.gymId;
      if (adminGymId != null) {
        // Admin: authed real-gym endpoint (latest run, or its rejected list).
        page = await GymContentRepository(ApiClient()).fetchVideos(
          adminGymId,
          videoType: widget.tag,
          rejected: widget.rejected,
          limit: _kPageSize,
          offset: _dbOffset,
        );
      } else {
        // Public browser: unauthenticated template endpoint.
        page = await VideoApiClient(gymId: widget.gymId).fetchFeed(
          videoType: widget.tag,
          rejected: widget.rejected,
          limit: _kPageSize,
          offset: _dbOffset,
        );
      }
      if (!mounted) return;
      setState(() {
        _videos.addAll(page.videos);
        _total = page.total;
        // Advance the DB cursor by the page size requested, not by the number
        // of videos returned — the backend may skip rows that fail validation,
        // and using the rendered count as the next offset would re-fetch those
        // rows and produce duplicate tiles.
        _dbOffset += _kPageSize;
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
          tiles: [
            for (final v in _videos)
              _tile(
                v,
                rejected: widget.rejected,
                onRemove: widget.enableRemove ? _remove : null,
              ),
          ],
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

/// Confirm-with-"why" then remove a queried (web_query) video from the admin
/// gym's feed (the backend logs the reason). Returns true on success so the
/// caller can drop the tile locally (no refetch). Admin only.
Future<bool> confirmAndRemoveGenreVideo(
  BuildContext context,
  Video video,
) async {
  final adminGymId = selectedGym.gymId;
  if (adminGymId == null) return false;
  final reason = await VideoCurationDialog.show(
    context,
    videoTitle: video.title.isNotEmpty ? video.title : 'this video',
    teachAgent: true,
    mode: VideoCurationMode.remove,
  );
  if (reason == null) return false;
  try {
    await GymContentRepository(ApiClient()).removeVideo(
      adminGymId,
      video.videoId,
      reason: reason.isEmpty ? null : reason,
    );
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn’t remove that video. Try again.')),
      );
    }
    return false;
  }
}

/// Confirm-with-"why" then "Keep" a rejected video (un-reject → back to the
/// served feed). The optional reason is stored as `accept_reason` and teaches
/// the feed-learning refiner to surface videos like it. Returns true on success
/// so the caller can drop it from the rejected list.
Future<bool> keepGenreVideo(BuildContext context, Video video) async {
  final adminGymId = selectedGym.gymId;
  if (adminGymId == null) return false;
  final reason = await VideoCurationDialog.show(
    context,
    videoTitle: video.title.isNotEmpty ? video.title : 'this video',
    teachAgent: true,
    mode: VideoCurationMode.keep,
  );
  if (reason == null) return false;
  try {
    await GymContentRepository(ApiClient()).keepVideo(
      adminGymId,
      video.videoId,
      reason: reason.isEmpty ? null : reason,
    );
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn’t keep that video. Try again.')),
      );
    }
    return false;
  }
}

Widget _tile(
  Video v, {
  bool rejected = false,
  void Function(Video)? onRemove,
}) => VideoTile(
  // Use the stored thumbnail; show nothing when there isn't one.
  thumbnail: v.thumbnailUrl.isNotEmpty ? NetworkImage(v.thumbnailUrl) : null,
  avatar: NetworkImage(v.channelAvatarUrl),
  title: v.title,
  meta: v.metaLabel,
  rejected: rejected,
  onTap: () => openVideoInNewTab(v.url),
  // When wired (admin), a real remove (with logged why); else VideoTile falls
  // back to its internal curation dialog (public/rejected demo).
  onRemove: onRemove != null ? () => onRemove(v) : null,
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
  final IconData? icon;

  const _FeedMessage(this.message, {this.icon});
  const _FeedMessage.loading()
      : message = null,
        icon = null;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(
        child: message == null
            ? const AppSpinner()
            : Column(
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingMedium,
                children: [
                  if (icon != null)
                    Icon(
                      icon,
                      size: DesignConstants.iconSizeMedium,
                      weight: DesignConstants.iconWeight,
                      color: DesignConstants.text3rd,
                    ),
                  Text(
                    message!,
                    style: DesignConstants.p.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
      ),
    );
  }
}
