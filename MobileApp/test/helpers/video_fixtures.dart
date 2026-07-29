import 'package:mobile_app/features/videos/data/video.dart';

/// A fabricated feed plus the orderings the selectors will derive from
/// it, so a test can assert against the same expectations the screen
/// computes.
class VideoFeed {
  const VideoFeed({
    required this.videos,
    required this.tags,
    required this.groups,
  });

  /// Every video, already in relevancy order — so `videos.first` is the
  /// hero the screen will feature.
  final List<Video> videos;

  /// Wire tag values in the order their sections will appear.
  final List<String> tags;

  /// Wire `big_group` values in the order their pills will appear.
  final List<String> groups;
}

const List<String> _kGroupNames = [
  'educational',
  'entertainment',
  'community',
  'behind_the_scenes',
];

/// Builds a feed of `tags * perTag` videos spread over [tags] tags and
/// [groups] big groups.
///
/// Tags and groups are interleaved across the relevancy order, which is
/// what makes the derived orderings predictable: the first video
/// carries the first tag and the first group, the second the second of
/// each, and so on.
VideoFeed videoFeed({
  required int tags,
  required int groups,
  int perTag = 3,
}) {
  assert(groups <= _kGroupNames.length);
  final tagNames = [for (var i = 0; i < tags; i++) 'technique_${i + 1}'];
  final groupNames = _kGroupNames.take(groups).toList();

  final videos = <Video>[
    for (var i = 0; i < tags * perTag; i++)
      Video(
        url: 'https://videos.test/${i + 1}',
        title: 'Clip ${i + 1}',
        thumbnailUrl: 'https://videos.test/${i + 1}/thumb.jpg',
        channelName: 'Channel ${i + 1}',
        channelUrl: 'https://videos.test/channel/${i + 1}',
        channelAvatarUrl: 'https://videos.test/channel/${i + 1}/pfp.jpg',
        viewCount: 100000 - i * 137,
        relevanceIndex: i,
        tags: [tagNames[i % tags]],
        bigGroups: [groupNames[i % groups]],
        isGood: true,
      ),
  ];

  return VideoFeed(videos: videos, tags: tagNames, groups: groupNames);
}
