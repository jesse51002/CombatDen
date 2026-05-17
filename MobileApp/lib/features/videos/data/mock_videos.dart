/// Plain Dart model for a video card in the prototype.
///
/// Field names mirror what the eventual API will return so the swap from
/// hardcoded data to a real repository is mechanical.
class MockVideo {
  const MockVideo({
    required this.id,
    required this.title,
    required this.creatorName,
    required this.creatorPfpAsset,
    required this.thumbnailAsset,
    required this.viewsLabel,
    required this.sponsorLabel,
    required this.category,
  });

  final String id;
  final String title;
  final String creatorName;
  final String creatorPfpAsset;
  final String thumbnailAsset;
  final String viewsLabel;
  final String sponsorLabel;
  final String category;

  /// "USDC by Rokas Leo ‧ 350K views"
  String get metaLabel => '$sponsorLabel by $creatorName ‧ $viewsLabel';
}

const String _kCreatorPfp = 'creator_pfp.png';

const List<MockVideo> mockVideos = [
  MockVideo(
    id: 'self-defense',
    title: 'We Put Fighters in Self Defense Training',
    creatorName: 'Rokas Leo',
    creatorPfpAsset: _kCreatorPfp,
    thumbnailAsset: 'video_thumb_self_defense.png',
    viewsLabel: '350K views',
    sponsorLabel: 'USDC',
    category: 'Featured',
  ),
  MockVideo(
    id: 'boxing-ring',
    title: 'We Put Fighters in Self Defense Training',
    creatorName: 'Rokas Leo',
    creatorPfpAsset: _kCreatorPfp,
    thumbnailAsset: 'video_thumb_boxing_ring.png',
    viewsLabel: '350K views',
    sponsorLabel: 'USDC',
    category: 'Your Next Watch',
  ),
  MockVideo(
    id: 'netflix-red',
    title: 'Mauy Thai Basics (Don’t look lik)',
    creatorName: 'Rokas Leo',
    creatorPfpAsset: _kCreatorPfp,
    thumbnailAsset: 'video_thumb_netflix_red.png',
    viewsLabel: '350K views',
    sponsorLabel: 'USDC',
    category: 'Your Next Watch',
  ),
  MockVideo(
    id: 'muay-thai-pad',
    title: 'Mauy Thai Basics (Don’t look lik)',
    creatorName: 'Rokas Leo',
    creatorPfpAsset: _kCreatorPfp,
    thumbnailAsset: 'video_thumb_muay_thai_drills.png',
    viewsLabel: '350K views',
    sponsorLabel: 'USDC',
    category: 'Level up your skills',
  ),
  MockVideo(
    id: 'krav-maga-specs',
    title: 'We Put Fighters in Self Defense Training',
    creatorName: 'Rokas Leo',
    creatorPfpAsset: _kCreatorPfp,
    thumbnailAsset: 'video_thumb_krav_maga_specs.png',
    viewsLabel: '350K views',
    sponsorLabel: 'USDC',
    category: 'Level up your skills',
  ),
  MockVideo(
    id: 'netflix-fight',
    title: 'Mauy Thai Basics (Don’t look lik)',
    creatorName: 'Rokas Leo',
    creatorPfpAsset: _kCreatorPfp,
    thumbnailAsset: 'video_thumb_netflix_fight.png',
    viewsLabel: '350K views',
    sponsorLabel: 'USDC',
    category: 'Fights Highlights',
  ),
  MockVideo(
    id: 'krav-skit',
    title: 'Mauy Thai Basics (Don’t look lik)',
    creatorName: 'Rokas Leo',
    creatorPfpAsset: _kCreatorPfp,
    thumbnailAsset: 'video_thumb_krav_skit.png',
    viewsLabel: '350K views',
    sponsorLabel: 'USDC',
    category: 'Martial Arts Skits',
  ),
];

/// Featured "main video" up top — first item.
const MockVideo mockFeaturedVideo = MockVideo(
  id: 'self-defense',
  title: 'We Put Fighters in Self Defense Training',
  creatorName: 'Rokas Leo',
  creatorPfpAsset: _kCreatorPfp,
  thumbnailAsset: 'video_thumb_self_defense.png',
  viewsLabel: '350K views',
  sponsorLabel: 'USDC',
  category: 'Featured',
);

/// "Drill of the Day" video shown on the post-class screen. Same card
/// as the post-booking recommendation — different thumbnail and copy.
const MockVideo mockDrillOfTheDay = MockVideo(
  id: 'drill-of-the-day',
  title: 'Head movement tutorial',
  creatorName: 'Rokas Leo',
  creatorPfpAsset: _kCreatorPfp,
  thumbnailAsset: 'video_thumb_muay_thai_drills.png',
  viewsLabel: '350K views',
  sponsorLabel: 'USDC',
  category: 'Drill of the Day',
);

/// "Video Before Class" recommendation surfaced after booking a class.
const MockVideo mockVideoBeforeClass = MockVideo(
  id: 'before-class-recc',
  title: '5 Things You Should Know Before Joining a Martial Arts Gym',
  creatorName: 'Rokas Leo',
  creatorPfpAsset: _kCreatorPfp,
  thumbnailAsset: 'video_thumb_netflix_red.png',
  viewsLabel: '350K views',
  sponsorLabel: 'USDC',
  category: 'Video Before Class',
);

/// "Technique of the Day" big card — uses the muay thai drills thumb.
const MockVideo mockTechniqueOfTheDay = MockVideo(
  id: 'technique-of-the-day',
  title: 'We Put Fighters in Self Defense Training',
  creatorName: 'Rokas Leo',
  creatorPfpAsset: _kCreatorPfp,
  thumbnailAsset: 'video_thumb_muay_thai_drills.png',
  viewsLabel: '350K views',
  sponsorLabel: 'USDC',
  category: 'Technique of the Day',
);

/// Specific (Learn / Fighting Lessons) feed.
const List<MockVideo> mockFightingLessons = [
  MockVideo(
    id: 'gym-questions',
    title:
        'How to Get Started in Muay Thai (or any martial art!) | '
        'Beginner Tips for Y...',
    creatorName: 'Rokas Leo',
    creatorPfpAsset: _kCreatorPfp,
    thumbnailAsset: 'video_thumb_gym_questions.png',
    viewsLabel: '350K views',
    sponsorLabel: 'USDC',
    category: 'Fighting Lessons',
  ),
  MockVideo(
    id: 'muay-thai-title',
    title: 'How I Would Train Muay Thai/Kickboxing If I Was A Beginner…',
    creatorName: 'Rokas Leo',
    creatorPfpAsset: _kCreatorPfp,
    thumbnailAsset: 'video_thumb_muay_thai_title.png',
    viewsLabel: '350K views',
    sponsorLabel: 'USDC',
    category: 'Fighting Lessons',
  ),
  MockVideo(
    id: 'muay-thai-drills',
    title: 'Muay Thai Drills',
    creatorName: 'Rokas Leo',
    creatorPfpAsset: _kCreatorPfp,
    thumbnailAsset: 'video_thumb_muay_thai_drills.png',
    viewsLabel: '350K views',
    sponsorLabel: 'USDC',
    category: 'Fighting Lessons',
  ),
  MockVideo(
    id: 'shadow-boxing',
    title: '10 Muay Thai Shadow Boxing Drills For Beginners',
    creatorName: 'Rokas Leo',
    creatorPfpAsset: _kCreatorPfp,
    thumbnailAsset: 'video_thumb_shadow_boxing.png',
    viewsLabel: '350K views',
    sponsorLabel: 'USDC',
    category: 'Fighting Lessons',
  ),
];
