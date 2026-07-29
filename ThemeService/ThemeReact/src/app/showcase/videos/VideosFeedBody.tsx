// Ports ../../../../../../MobileApp/lib/features/videos/presentation/widgets/
// videos_feed_body.dart — the feed area below the topbar: the filter pills, the
// featured hero, and one section per genre.
//
// Resolves the tenant's `videos_format` slot and delegates to one of the five
// arrangements in ./layouts/, each of which arranges the SAME
// ./videosLayoutData.ts payload. An arrangement may move these and change their
// prominence. It may not drop one, add one, or reach past the payload for data
// of its own — ./__tests__/videosFormats.test.tsx is the gate that proves it,
// mirroring `MobileApp/test/videos_invariants_test.dart`.
//
// Returns a FRAGMENT, for the same reason Dart returns a sliver rather than a
// box: the screen owns one scroll for topbar and feed together, so an
// arrangement that pins its filter (or its rail) has to sit in that same scroll
// container. A wrapper div here would give the sticky bands a new containing
// block and they would pin to the feed instead of to the phone screen.

import { FORMAT_SLOTS, VIDEOS_FORMATS, useFormat } from '../formats';

import { VideosCarouselRows } from './layouts/VideosCarouselRows';
import { VideosEditorialStack } from './layouts/VideosEditorialStack';
import { VideosMosaic } from './layouts/VideosMosaic';
import { VideosShortsColumn } from './layouts/VideosShortsColumn';
import { VideosTagRail } from './layouts/VideosTagRail';
import type { VideosLayoutData } from './videosLayoutData';

export interface VideosFeedBodyProps {
  data: VideosLayoutData;
}

export function VideosFeedBody({ data }: VideosFeedBodyProps) {
  const format = useFormat(FORMAT_SLOTS.videos, VIDEOS_FORMATS, 'carouselRows');

  // Dart's `switch` over `VideosFormat`, exhaustive over the same five values.
  switch (format) {
    case 'editorialStack':
      return <VideosEditorialStack data={data} />;
    case 'mosaic':
      return <VideosMosaic data={data} />;
    case 'shortsColumn':
      return <VideosShortsColumn data={data} />;
    case 'tagRail':
      return <VideosTagRail data={data} />;
    case 'carouselRows':
      return <VideosCarouselRows data={data} />;
  }
}
