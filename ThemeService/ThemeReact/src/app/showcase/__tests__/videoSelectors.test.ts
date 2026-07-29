// The pure half of the Video screen (../videos/videoSelectors.ts), which ports
// `MobileApp/lib/features/videos/data/gym_video_selectors.dart` +
// `gym_video_helpers.dart`.
//
// Two things are worth pinning here. The GROUPING contract — first-appearance
// order, one carousel per card, `unknown` skipped — is what decides both the
// tab strip and the carousel list, so a regression there silently reshapes the
// whole screen. And `formatViewCount`'s BOUNDARIES are the arithmetic most
// likely to drift: the 1000 / 1_000_000 / 10M thresholds each switch format.

import { describe, expect, it } from 'vitest';

import type { ShowcaseVideo } from '../showcaseContent';
import { bundledVideos } from '../showcaseVideoDefaults';
import {
  featuredVideo,
  formatViewCount,
  genreLabel,
  genreSections,
  genresInFeed,
  levelUpVideos,
  videoMetaLabel,
} from '../videos/videoSelectors';
import { videoTabLabels } from '../videos/VideoShowcase';

function video(videoId: string, genre: string, viewCount: number | null = 1000): ShowcaseVideo {
  return {
    videoId,
    title: `title ${videoId}`,
    genre,
    channelName: `channel ${videoId}`,
    viewCount,
    thumbnailUrl: `https://example.test/${videoId}.jpg`,
    channelAvatarUrl: '',
  };
}

describe('formatViewCount', () => {
  it('prints a hidden count as nothing, so the "views" clause can be dropped', () => {
    expect(formatViewCount(null)).toBe('');
  });

  it('holds each of the three format boundaries', () => {
    expect(formatViewCount(942)).toBe('942');
    expect(formatViewCount(999)).toBe('999');
    // 1000 switches to K, and the K branch FLOORS rather than rounding.
    expect(formatViewCount(1000)).toBe('1K');
    expect(formatViewCount(168441)).toBe('168K');
    expect(formatViewCount(999999)).toBe('999K');
    // 1_000_000 switches to M, one decimal under 10M...
    expect(formatViewCount(1000000)).toBe('1.0M');
    expect(formatViewCount(1240000)).toBe('1.2M');
    expect(formatViewCount(9900000)).toBe('9.9M');
    // ...and whole millions at or above it.
    expect(formatViewCount(10000000)).toBe('10M');
    expect(formatViewCount(12500000)).toBe('12M');
  });
});

describe('videoMetaLabel', () => {
  it('drops the views clause when the channel hides its stats', () => {
    expect(videoMetaLabel(video('a', 'educational', null))).toBe('channel a');
  });

  it('joins channel and views with the Dart hyphenation point', () => {
    expect(videoMetaLabel(video('a', 'educational', 168441))).toBe('channel a ‧ 168K views');
  });
});

describe('genreLabel', () => {
  it('capitalises the wire value, as VideoGenre.label does', () => {
    expect(genreLabel('educational')).toBe('Educational');
    expect(genreLabel('professional')).toBe('Professional');
    expect(genreLabel('')).toBe('');
  });
});

describe('genresInFeed', () => {
  it('returns distinct genres in FIRST-APPEARANCE order, not sorted', () => {
    const feed = [
      video('1', 'vlog'),
      video('2', 'educational'),
      video('3', 'vlog'),
      video('4', 'interview'),
    ];
    expect(genresInFeed(feed)).toEqual(['vlog', 'educational', 'interview']);
  });

  it('skips untagged and unknown cards — neither maps to a tab the portal accepts', () => {
    const feed = [video('1', ''), video('2', 'unknown'), video('3', 'educational')];
    expect(genresInFeed(feed)).toEqual(['educational']);
  });

  it('is empty for an empty feed', () => {
    expect(genresInFeed([])).toEqual([]);
  });
});

describe('featuredVideo', () => {
  it('is the first card of the already-ranked page', () => {
    const feed = [video('1', 'educational'), video('2', 'vlog')];
    expect(featuredVideo(feed)?.videoId).toBe('1');
  });

  it('is null for an empty feed', () => {
    expect(featuredVideo([])).toBeNull();
  });
});

describe('genreSections', () => {
  it('claims each card for its single genre, in first-appearance order', () => {
    const feed = [
      video('1', 'vlog'),
      video('2', 'educational'),
      video('3', 'vlog'),
      video('4', 'educational'),
    ];
    expect(genreSections(feed)).toEqual([
      { genre: 'vlog', videos: [feed[0], feed[2]] },
      { genre: 'educational', videos: [feed[1], feed[3]] },
    ]);
  });

  it('gives untagged and unknown cards no carousel at all', () => {
    const feed = [video('1', 'unknown'), video('2', '')];
    expect(genreSections(feed)).toEqual([]);
  });

  it('keeps the featured card in its own carousel — the real screen does too', () => {
    // `videos_feed_body.dart` calls featuredCard and genreSections over the SAME
    // list and neither excludes the other's pick. Pinned so the port is not
    // "fixed" into a divergence from the app it mirrors.
    const feed = [video('1', 'educational'), video('2', 'educational')];
    const first = featuredVideo(feed);
    expect(first?.videoId).toBe('1');
    expect(genreSections(feed)[0]?.videos.map((v) => v.videoId)).toEqual(['1', '2']);
  });
});

describe('levelUpVideos', () => {
  it('narrows to educational and caps at the portal request limit', () => {
    const feed = [
      ...Array.from({ length: 12 }, (_, i) => video(`e${String(i)}`, 'educational')),
      video('v', 'vlog'),
    ];
    const levelUp = levelUpVideos(feed);
    expect(levelUp).toHaveLength(10);
    expect(levelUp.every((v) => v.genre === 'educational')).toBe(true);
  });

  it('is empty when the tenant has no educational videos, so the section self-hides', () => {
    expect(levelUpVideos([video('1', 'vlog')])).toEqual([]);
  });
});

describe('videoTabLabels', () => {
  it('puts "All" first, then one label per genre in the feed', () => {
    const feed = [video('1', 'educational'), video('2', 'vlog')];
    expect(videoTabLabels(feed)).toEqual(['All', 'Educational', 'Vlog']);
  });
});

describe('bundled feeds', () => {
  // The eight feeds are the offline fallback the whole Video screen renders
  // from, and both new screens are unusable if one is thin or malformed.
  const GROUPS = [
    'Fighting',
    'Yoga',
    'Pilates',
    'Barre',
    'HIIT',
    'Cardio',
    'Dance',
    'Wellness',
  ];

  it('carries a feed for every showcase group', () => {
    for (const group of GROUPS) {
      expect(bundledVideos(group).length).toBeGreaterThan(0);
    }
  });

  it('falls back to the default group for an unknown or null category', () => {
    expect(bundledVideos('Quidditch')).toEqual(bundledVideos('Fighting'));
    expect(bundledVideos(null)).toEqual(bundledVideos('Fighting'));
  });

  it('gives every group enough depth for a hero plus three carousels', () => {
    for (const group of GROUPS) {
      const feed = bundledVideos(group);
      expect(genreSections(feed).length).toBeGreaterThanOrEqual(3);
      expect(feed.length).toBeGreaterThanOrEqual(10);
    }
  });

  it('gives every group an educational slice, so Profile never renders headerless', () => {
    for (const group of GROUPS) {
      expect(levelUpVideos(bundledVideos(group)).length).toBeGreaterThanOrEqual(3);
    }
  });

  it('carries a unique id, a title and a thumbnail on every card', () => {
    for (const group of GROUPS) {
      const feed = bundledVideos(group);
      expect(new Set(feed.map((v) => v.videoId)).size).toBe(feed.length);
      for (const item of feed) {
        expect(item.title).not.toBe('');
        expect(item.thumbnailUrl).not.toBe('');
        expect(item.channelName).not.toBe('');
      }
    }
  });
});
