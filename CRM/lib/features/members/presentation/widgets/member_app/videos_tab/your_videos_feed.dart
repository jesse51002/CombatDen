import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/members/data/gym_content_repository.dart';
import 'package:crm/features/members/data/video_feed.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/add_custom_video_button.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/add_video_dialog.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/video_wrap_grid.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/view_all_button.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/your_video_tile.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';
import 'package:crm/shared/widgets/horizontal_scroller.dart';
import 'package:crm/shared/widgets/section_card.dart';

/// The gym's own "Your videos" feed — the real, editable `gym_video_feed` for
/// the admin's selected gym (UUID-keyed, authed). The owner adds videos by
/// pasting a YouTube link and removes them inline; every tile opens its watch
/// page in a new browser tab.
///
/// Two layouts off the same fetch/add/remove core:
///  - [YourVideosFeed.preview] — the capped strip inside the "All" view, with a
///    "View all" jump and the add action beneath it.
///  - [YourVideosFeed.full] — the "View all" grid (paginated "Load more"), with
///    the add action leading it.
class YourVideosFeed extends StatefulWidget {
  /// The real gym UUID whose feed this edits.
  final String gymId;

  /// Preview strip (capped, in "All") vs the full paginated grid ("View all").
  final bool preview;

  /// Jump to the full "View all" grid; only set in the preview layout.
  final VoidCallback? onViewAll;

  const YourVideosFeed.preview({
    super.key,
    required this.gymId,
    required this.onViewAll,
  }) : preview = true;

  const YourVideosFeed.full({super.key, required this.gymId})
    : preview = false,
      onViewAll = null;

  @override
  State<YourVideosFeed> createState() => _YourVideosFeedState();
}

class _YourVideosFeedState extends State<YourVideosFeed> {
  // The preview strip caps at ten tiles; the full grid pages by this many.
  static const int _previewCap = 10;
  static const int _pageSize = 24;

  final List<Video> _videos = [];
  int _total = 0;
  bool _loading = false;
  bool _errored = false;
  bool _loadedFirst = false;

  GymContentRepository get _repo => GymContentRepository(ApiClient());
  int get _limit => widget.preview ? _previewCap : _pageSize;
  bool get _hasMore => !widget.preview && _videos.length < _total;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  @override
  void didUpdateWidget(YourVideosFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The admin switched gyms — drop the old feed and reload.
    if (oldWidget.gymId != widget.gymId) _reload();
  }

  void _reload() {
    setState(() {
      _videos.clear();
      _total = 0;
      _loadedFirst = false;
      _errored = false;
    });
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _errored = false;
    });
    try {
      final page = await _repo.fetchVideos(
        widget.gymId,
        // "Your videos" is the owner section (run-independent); the imported
        // (latest-run) videos live in the genre rows.
        owner: true,
        limit: _limit,
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

  Future<void> _add() async {
    // Step 1: paste a link, the dialog looks it up + shows its details, and the
    // owner confirms. The dialog returns the URL only after that confirmation.
    final url = await AddVideoDialog.show(
      context,
      onLookup: (link) => _repo.lookupVideo(widget.gymId, link),
    );
    if (url == null || !mounted) return;
    try {
      // Step 2: commit the add (the backend re-fetches the metadata).
      final added = await _repo.addVideo(widget.gymId, url);
      if (!mounted) return;
      setState(() {
        // Surface the new tile at the front immediately. If it was already in
        // the feed (idempotent add), move it up without double-counting.
        final existed = _videos.any((v) => v.videoId == added.videoId);
        _videos.removeWhere((v) => v.videoId == added.videoId);
        _videos.insert(0, added);
        if (!existed) _total += 1;
      });
      _toast('Added to your feed.');
    } catch (_) {
      if (!mounted) return;
      _toast('Couldn’t add that video. Check the link and try again.');
    }
  }

  Future<void> _remove(Video video) async {
    // Manual removes are a plain confirmation — no "why". The removal is still
    // recorded server-side (with no reason).
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: 'Remove this video?',
      message: video.title.isNotEmpty
          ? 'Remove “${video.title}” from your feed?'
          : 'Remove this video from your feed?',
      confirmLabel: 'Remove',
      confirmColor: DesignConstants.badRed,
    );
    if (!confirmed || !mounted) return;
    try {
      // Owner-section remove: drop it from "Your videos" (and the owned pool row
      // if it's a manual custom video).
      await _repo.removeVideo(widget.gymId, video.videoId, owner: true);
      if (!mounted) return;
      setState(() {
        _videos.removeWhere((v) => v.videoId == video.videoId);
        if (_total > 0) _total -= 1;
      });
    } catch (_) {
      if (!mounted) return;
      _toast('Couldn’t remove that video. Try again.');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return widget.preview ? _buildPreview() : _buildFull();
  }

  Widget _buildPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Row(
          children: [
            Expanded(child: Text('Your videos', style: DesignConstants.h3)),
            ViewAllButton(onTap: widget.onViewAll ?? () {}),
          ],
        ),
        _previewBody(),
        AddCustomVideoButton(onPressed: _add),
      ],
    );
  }

  Widget _previewBody() {
    if (!_loadedFirst) {
      return _errored
          ? const _Msg('Could not load your videos.')
          : const _Msg.loading();
    }
    if (_videos.isEmpty) {
      return const _Msg('No videos yet — add one to get started.');
    }
    return HorizontalScroller(
      children: [
        for (final v in _videos.take(_previewCap))
          feedVideoTile(v, onRemove: () => _remove(v)),
      ],
    );
  }

  Widget _buildFull() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingBig,
      children: [
        AddCustomVideoButton(onPressed: _add),
        _fullBody(),
      ],
    );
  }

  Widget _fullBody() {
    if (!_loadedFirst) {
      return _errored
          ? const _Msg('Could not load your videos.')
          : const _Msg.loading();
    }
    if (_videos.isEmpty) {
      return const _Msg('No videos yet — add one to get started.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        VideoWrapGrid(
          tiles: [
            for (final v in _videos) feedVideoTile(v, onRemove: () => _remove(v)),
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

/// A small loading spinner / message card for the feed's empty + loading +
/// error states (mirrors the member feed's inline messages).
class _Msg extends StatelessWidget {
  final String? message;

  const _Msg(this.message);
  const _Msg.loading() : message = null;

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
