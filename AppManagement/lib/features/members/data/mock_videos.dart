/// Hardcoded data for the Member App "Videos" tab.
///
/// Mirrors the VideoService video-brief contract
/// (`VideoService/schema/videos_config.py`): a [VideoBrief] of prose
/// descriptions plus the search prompts the agent generates, alongside
/// the videos those searches surfaced. The admin reads this here and
/// re-derives it through the agentic edit screen. Field names track the
/// API so the swap to real data stays mechanical.
library;

/// The fixed VideoService genre vocabulary. [unknown] is the resilient
/// fallback for any wire value the app doesn't recognize yet.
enum VideoType {
  entertainment('Entertainment'),
  educational('Educational'),
  tutorial('Tutorial'),
  informative('Informative'),
  news('News'),
  interview('Interview'),
  vlog('Vlog'),
  behindTheScenes('Behind the scenes'),
  professional('Professional'),
  clips('Clips'),
  fun('Fun'),
  unknown('Unknown');

  const VideoType(this.label);

  /// Title-case label for display on tag chips.
  final String label;
}

/// One generated YouTube search prompt and the genres it spans.
class VideoSearch {
  final String query;
  final List<VideoType> tags;

  const VideoSearch({required this.query, required this.tags});
}

/// The prose + search surface the agent authors for this gym.
class VideoBrief {
  final String companyName;
  final String type;

  /// Kinds of videos worth surfacing for this gym.
  final String videosDesc;

  /// Within-niche content the gym explicitly pushes back on.
  final String avoidDesc;

  final List<VideoSearch> searches;
  final List<String> priorityChannels;

  const VideoBrief({
    required this.companyName,
    required this.type,
    required this.videosDesc,
    required this.avoidDesc,
    required this.searches,
    required this.priorityChannels,
  });
}

/// A video surfaced into the gym's feed (pulled, intro, or custom).
class ManagedVideo {
  final String title;
  final String thumbnailAsset;
  final String channelName;
  final String channelAvatarAsset;

  /// Null when the channel hides its view stats.
  final int? viewCount;

  /// Display category that drives carousel grouping in the feed.
  final String category;

  const ManagedVideo({
    required this.title,
    required this.thumbnailAsset,
    required this.channelName,
    required this.channelAvatarAsset,
    required this.viewCount,
    required this.category,
  });
}

class MockVideosData {
  final VideoBrief brief;

  /// The single special "intro" video, shown first in "Your videos" with
  /// an intro pill. The live member feed comes from the API, not here.
  final ManagedVideo? introVideo;

  /// The gym's own uploads.
  final List<ManagedVideo> customVideos;

  const MockVideosData({
    required this.brief,
    required this.introVideo,
    required this.customVideos,
  });
}

const MockVideosData kMockVideos = MockVideosData(
  brief: VideoBrief(
    companyName: 'Apex MMA',
    type: 'Mixed martial arts gym',
    videosDesc:
        'Mixed martial arts taught as one complete game: striking, '
        'wrestling, and submission grappling drilled to work together. '
        'Worth surfacing are technique tutorials that bridge ranges, elite '
        'competition footage that shows the sport at the top level, '
        'training-camp vlogs, breakdowns of how fights are actually won, '
        'and the cleanest highlight and finish reels.',
    avoidDesc:
        'Within-MMA content the gym pushes back on: street-fight and '
        'untrained brawl clips, "martial art X is useless" rage-bait, '
        'single-style purists dismissing the rest of the game, and grimy '
        'blood-and-bruises content that glorifies damage over craft.',
    searches: [
      VideoSearch(
        query: 'mma fundamentals striking to takedown tutorial',
        tags: [VideoType.tutorial, VideoType.educational],
      ),
      VideoSearch(
        query: 'UFC fight night full highlights',
        tags: [
          VideoType.professional,
          VideoType.clips,
          VideoType.entertainment,
        ],
      ),
      VideoSearch(
        query: 'inside an mma fight camp vlog',
        tags: [VideoType.vlog, VideoType.behindTheScenes],
      ),
      VideoSearch(
        query: 'how mma fights are actually won breakdown',
        tags: [VideoType.informative, VideoType.educational],
      ),
      VideoSearch(
        query: 'best mma knockouts and submissions compilation',
        tags: [VideoType.clips, VideoType.entertainment, VideoType.fun],
      ),
    ],
    priorityChannels: ['UFC', 'BJJ Fanatics'],
  ),
  introVideo: ManagedVideo(
    title: 'Welcome to Apex MMA',
    thumbnailAsset: 'assets/images/class_muay_thai_session.png',
    channelName: 'Apex MMA',
    channelAvatarAsset: 'assets/images/pfp_amy_traver.png',
    viewCount: null,
    category: 'Intro',
  ),
  customVideos: [
    ManagedVideo(
      title: 'Coach Justin: guard retention seminar',
      thumbnailAsset: 'assets/images/class_bjj_nogi_today.png',
      channelName: 'Apex MMA',
      channelAvatarAsset: 'assets/images/pfp_justin_stemmons.png',
      viewCount: null,
      category: 'Custom',
    ),
    ManagedVideo(
      title: 'Fight night recap: our team at Regionals',
      thumbnailAsset: 'assets/images/class_muay_thai_wed.png',
      channelName: 'Apex MMA',
      channelAvatarAsset: 'assets/images/pfp_sylvia_crivia.png',
      viewCount: 3400,
      category: 'Custom',
    ),
  ],
);
