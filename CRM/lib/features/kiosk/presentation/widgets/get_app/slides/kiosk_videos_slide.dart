import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_showcase_slide.dart';
import 'package:crm/features/members/data/video_feed.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/video_format_helpers.dart';

/// The video card's 16:9 thumbnail.
const double _kThumbAspect = 16 / 9;

/// The channel avatar disc.
const double _kAvatarSize = 28.0;

/// The play disc floating on the thumbnail.
const double _kPlayDiscSize = 30.0;

/// Slide 3 — "Watch videos": the head of THIS gym's own curated feed, drawn as
/// the member app's video card.
///
/// **Data source: the gym's REAL feed.** The cubit fetches
/// `GET /api/v1/gyms/{gymId}/videos` once at kiosk entry and caches it, so
/// these are the gym's actual videos — real titles, real thumbnails, real view
/// counts. The one thing this must never render is `selectedGym.detail`: that
/// showcase belongs to a DEFAULT content gym, and putting its videos here
/// would show another gym's feed to this gym's members.
///
/// The slide is only built when the feed is non-empty — an empty or failed
/// feed omits the slide (and its dot) entirely rather than standing in
/// anything, so [videos] here is always populated.
///
/// The card anatomy is the MEMBER APP's video card, not the CRM `VideoTile`
/// (which carries admin Remove/Edit actions): this is a picture of the app
/// being marketed, not an admin surface.
class KioskVideosSlide extends StatelessWidget {
  final List<Video> videos;

  const KioskVideosSlide({super.key, required this.videos});

  @override
  Widget build(BuildContext context) {
    return KioskSlideBody(
      // Centred fixed-width cards, so one video reads as deliberate rather
      // than as a half-empty grid.
      content: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          for (final video in videos)
            SizedBox(
              width: DesignConstants.kioskVideoCardWidth,
              child: _VideoCard(video: video),
            ),
        ],
      ),
      caption: 'Technique breakdowns, picked for your gym.',
    );
  }
}

/// One video as the app's feed card: a 16:9 thumbnail with the play disc,
/// then the channel avatar beside the title + view count.
class _VideoCard extends StatelessWidget {
  final Video video;

  const _VideoCard({required this.video});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: DesignConstants.surface,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: Border.all(color: DesignConstants.line),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Thumb(imageUrl: video.thumbnailUrl),
          Padding(
            padding: const EdgeInsets.all(DesignConstants.spacingMedium),
            child: Row(
              spacing: DesignConstants.spacingMedium,
              children: [
                _Avatar(video: video),
                Expanded(child: _Meta(video: video)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String imageUrl;

  const _Thumb({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _kThumbAspect,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: DesignConstants.backgroundAlt),
          if (imageUrl.isNotEmpty)
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              // A stored thumbnail that won't load leaves the neutral fill
              // rather than a broken-image box on a member-facing screen.
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          const Center(child: _PlayDisc()),
        ],
      ),
    );
  }
}

/// The app's play affordance, shown as art — inert here (the kiosk plays
/// nothing; the member watches in the app).
class _PlayDisc extends StatelessWidget {
  const _PlayDisc();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kPlayDiscSize,
      height: _kPlayDiscSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DesignConstants.surface,
        shape: BoxShape.circle,
        boxShadow: DesignConstants.controlShadow,
      ),
      child: Icon(
        Symbols.play_arrow_sharp,
        fill: 1,
        size: DesignConstants.iconSizeSmall,
        color: DesignConstants.primaryColor,
      ),
    );
  }
}

/// The channel's avatar, falling back to its initials when the URL is missing
/// or won't load — a neutral disc, never a broken image.
class _Avatar extends StatelessWidget {
  final Video video;

  const _Avatar({required this.video});

  @override
  Widget build(BuildContext context) {
    final url = video.channelAvatarUrl;
    return Container(
      width: _kAvatarSize,
      height: _kAvatarSize,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DesignConstants.backgroundAlt,
        shape: BoxShape.circle,
        border: Border.all(color: DesignConstants.line),
      ),
      child: url.isEmpty
          ? _Initials(channelName: video.channelName)
          : Image.network(
              url,
              fit: BoxFit.cover,
              width: _kAvatarSize,
              height: _kAvatarSize,
              errorBuilder: (_, _, _) =>
                  _Initials(channelName: video.channelName),
            ),
    );
  }
}

class _Initials extends StatelessWidget {
  final String channelName;

  const _Initials({required this.channelName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        _initials(channelName),
        style: DesignConstants.kioskTag.copyWith(
          color: DesignConstants.text2nd,
        ),
      ),
    );
  }

  /// Up to two leading letters of the channel name ("Combat Culture" -> "CC").
  static String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return '';
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }
}

class _Meta extends StatelessWidget {
  final Video video;

  const _Meta({required this.video});

  @override
  Widget build(BuildContext context) {
    final views = formatViewCount(video.viewCount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingTiny,
      children: [
        Text(
          video.title,
          style: DesignConstants.kioskMicro,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // The channel hides its stats -> name the channel instead of showing
        // an empty line (or inventing a count).
        Text(
          views.isEmpty ? video.channelName : '$views views',
          style: DesignConstants.kioskTag.copyWith(
            fontWeight: FontWeight.w500,
            color: DesignConstants.text2nd,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
