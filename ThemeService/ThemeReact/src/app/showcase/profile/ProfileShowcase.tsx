// Ports ../../../../../../MobileApp/lib/features/profile/presentation/screens/
// profile_screen.dart — a visual clone of the member app's PROFILE tab: the
// name-only topbar, the "YOU HAVE A / N WEEK / STREAK" sparkle hero, the rank
// summary over its progress graph, the next-rank badge, and the "Videos to
// level up" carousel.
//
// THE SCREEN OWNS THE FRAME AND NOTHING ELSE. Scaffold, scroll, bottom nav —
// then the arrangement of the body is resolved from the tenant's `rank_format`
// slot and delegated to one of ./layouts/, each of which composes the same
// elements from the same `RankLayoutData`. That is the split Dart makes too,
// and it is why adding an arrangement never touches this file.
//
// NO DART SHOWCASE COUNTERPART. Like ../videos/VideoShowcase.tsx, the Flutter
// preview never carried this screen, so it is a first port straight from the
// member app.
//
// ONE OF THE TWO SHAPES. `profile_screen.dart` on main chooses between the rank
// shape and `RanklessProfileBody` on the gym FLAG `selectedMember.gymRankEnabled`.
// There is no gym in this browser and therefore no flag; the rank shape is the
// one worth previewing, because it is the one carrying the two belt slots and
// the graph — the rank-less shape is the same hero with the rank block removed,
// which would preview strictly less of the theme. The `rank == null` branch (a
// member at a rank-enabled gym who has not been graded yet) is likewise
// unreachable from a constant, so it is not ported.
//
// THE HERO IS ../rewards/SparkleHero.tsx, NOT A SECOND COPY. Dart reaches the
// same widget by a different route — `RankStreakHero` hands `SparkleHero` its
// three lines — and this island already has that component behind
// ../rewards/PointsHeadline.tsx. Same sparkle scatter, same clock, different
// copy.

import type { ShowcaseVideo } from '../showcaseContent';
import { FORMAT_SLOTS, RANK_FORMATS, useFormat } from '../formats';
import type { RankFormat } from '../formats';
import { ShowcaseBottomNav } from '../support/ShowcaseBottomNav';
import { ShowcaseScaffold } from '../support/ShowcaseScaffold';
import { levelUpVideos } from '../videos/videoSelectors';

import { RankBeltHero } from './layouts/RankBeltHero';
import { RankProgressFirst } from './layouts/RankProgressFirst';
import { RankSparkleStack } from './layouts/RankSparkleStack';
import { RankSplitRank } from './layouts/RankSplitRank';
import { RankStatTiles } from './layouts/RankStatTiles';
import type { RankLayoutData } from './rankLayoutData';
import styles from './ProfileShowcase.module.css';
import {
  SHOWCASE_PROFILE_POINTS_LABEL,
  SHOWCASE_PROFILE_STREAK_WEEKS,
  SHOWCASE_RANK,
  SHOWCASE_RANK_POINTS,
} from './mockRankProgress';

/** The default every surface in this island shares. */
const DEFAULT_GYM_NAME = 'Your Gym';

export interface ProfileShowcaseProps {
  /** The host gym's name. There is no gym in this browser. */
  gymName?: string;
  /** The host gym's real logo URL. Absent here. */
  gymLogoSrc?: string | undefined;
  /** The resolved feed; the level-up carousel is its educational head. */
  videos: readonly ShowcaseVideo[];
}

export function ProfileShowcase({
  gymName = DEFAULT_GYM_NAME,
  gymLogoSrc,
  videos,
}: ProfileShowcaseProps) {
  // The tenant's classified arrangement, or the one that ships. Resolved here
  // and nowhere else: a layout is handed its data, never a format.
  const format = useFormat(FORMAT_SLOTS.rank, RANK_FORMATS, 'sparkleStack');

  // `LevelUpVideosSection` asks the portal for `videoType: educational,
  // limit: 10`; there is no portal here, so the same narrowing runs over the
  // loaded feed. It hides itself when empty — see ./layouts/LevelUpVideos.tsx.
  const data: RankLayoutData = {
    gymName,
    gymLogoSrc,
    rank: SHOWCASE_RANK,
    points: SHOWCASE_RANK_POINTS,
    streakWeeks: SHOWCASE_PROFILE_STREAK_WEEKS,
    pointsLabel: SHOWCASE_PROFILE_POINTS_LABEL,
    levelUpVideos: levelUpVideos(videos),
  };

  return (
    <ShowcaseScaffold
      horizontalPadding="none"
      bodyScroll
      bottomNav={<ShowcaseBottomNav selected="rank" />}
    >
      {/*
        `SingleChildScrollView(padding: only(bottom: _kBottomScrollPadding))` —
        the room the persistent bottom nav needs, so the last carousel can
        scroll clear of it rather than ending underneath it.
      */}
      <div className={styles.profile}>
        <RankBody format={format} data={data} />
      </div>
    </ShowcaseScaffold>
  );
}

/** `switch (formatOverride ?? ThemeLayout.rank())`, exhaustive in both languages. */
function RankBody({ format, data }: { format: RankFormat; data: RankLayoutData }) {
  switch (format) {
    case 'sparkleStack':
      return <RankSparkleStack data={data} />;
    case 'beltHero':
      return <RankBeltHero data={data} />;
    case 'statTiles':
      return <RankStatTiles data={data} />;
    case 'progressFirst':
      return <RankProgressFirst data={data} />;
    case 'splitRank':
      return <RankSplitRank data={data} />;
  }
}
