// Ports ../../../../../../../MobileApp/lib/features/videos/presentation/layouts/
// videos_editorial_stack.dart — `VideosFormat.editorialStack`: no horizontal
// scrolling anywhere.
//
// The hero bleeds to both edges like a cover, then every genre becomes a
// vertical section of width-filling cards closed by a "view all" row. Slower to
// browse, far better for a tenant whose content is long-form and whose members
// read titles.
//
// NO SIDEWAYS SCROLL IS THE POINT, so the two places this island scrolls
// sideways are both gone here: the hero drops its inset instead of running past
// it, and every section is a `stack` rather than a `row`. The pill strip keeps
// its own overflow because a tenant's genre count is not ours to cap — it is
// the filter, not content, and Dart makes the same exception.

import { FeaturedVideoCard } from '../FeaturedVideoCard';
import { VideoCarouselSection } from '../VideoCarouselSection';
import { VideosFeedStatus } from '../VideosFeedStatus';
import type { VideosLayoutData } from '../videosLayoutData';
import { sectionTitle } from '../videosLayoutData';
import { VideosScopeTabs } from '../VideosScopeTabs';

import styles from './VideosEditorialStack.module.css';

export interface VideosEditorialStackProps {
  data: VideosLayoutData;
}

export function VideosEditorialStack({ data }: VideosEditorialStackProps) {
  const { featured } = data;
  return (
    <>
      <VideosScopeTabs data={data} />
      {/* `Column(stretch, spacing: spacingBig)`. */}
      <div className={styles.body}>
        {featured !== null && <FeaturedVideoCard video={featured} layout="bleed" />}
        {data.sections.map((section) => (
          // `Padding(horizontal: screenHorizontalPadding)` — the sections sit in
          // the gutter the hero deliberately ignores.
          <div key={section.genre} className={styles.sectionInset}>
            <VideoCarouselSection
              title={sectionTitle(section)}
              videos={section.videos}
              layout="stack"
            />
          </div>
        ))}
        {data.isEmpty && <VideosFeedStatus />}
      </div>
    </>
  );
}
