// Ports ../../../../../../MobileApp/lib/features/videos/presentation/widgets/
// video_carousel_section.dart — a titled section holding one genre's videos
// plus its "view all" affordance, in whichever of the four shapes the
// arrangement asked for.
//
// A SHAPE IS A PRESENTATION PROP. Every value renders the same title, the same
// "view all" action, and a card for every video in the section. What changes is
// the axis they run on and where the action sits — which is exactly the licence
// an arrangement has, and exactly the boundary
// ./__tests__/videosFormats.test.tsx enforces.
//
// The arrangement that places a section decides its horizontal inset — screen
// gutter, a narrower column beside a rail, or full bleed. The one exception is
// `row`, which insets its own header and pads its own scroll view, because its
// cards have to run past the gutter and off the edge.

import type { ShowcaseVideo } from '../showcaseContent';

import { VideoSectionColumn } from './sections/VideoSectionColumn';
import { VideoSectionGrid } from './sections/VideoSectionGrid';
import { VideoSectionRow } from './sections/VideoSectionRow';
import { VideoSectionTall } from './sections/VideoSectionTall';

/** `VideoSectionLayout` — how one genre's videos are arranged. */
export type VideoSectionLayout = 'row' | 'stack' | 'grid' | 'tall';

export interface VideoCarouselSectionProps {
  title: string;
  videos: readonly ShowcaseVideo[];
  layout?: VideoSectionLayout | undefined;
  /**
   * `row` only — the inline padding its header and scroll ends sit at. The
   * other three shapes are padded by their owner, so the value is theirs to
   * ignore. Defaults to the screen gutter, which is what the videos tab uses;
   * the profile's own row passes `big`.
   */
  inset?: 'screen' | 'big' | undefined;
}

export function VideoCarouselSection({
  title,
  videos,
  layout = 'row',
  inset = 'screen',
}: VideoCarouselSectionProps) {
  switch (layout) {
    case 'stack':
      return <VideoSectionColumn title={title} videos={videos} />;
    case 'grid':
      return <VideoSectionGrid title={title} videos={videos} />;
    case 'tall':
      return <VideoSectionTall title={title} videos={videos} />;
    case 'row':
      return <VideoSectionRow title={title} videos={videos} inset={inset} />;
  }
}
