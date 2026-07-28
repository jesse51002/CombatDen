// Ports ../../../../../../MobileApp/lib/features/profile/presentation/screens/
// profile_screen.dart — a visual clone of the member app's PROFILE tab: the
// name-only topbar, the "YOU HAVE A / N WEEK / STREAK" sparkle hero, the rank
// summary over its progress graph, the next-rank badge, and the "Videos to
// level up" carousel, with a full-bleed divider between each block.
//
// NO DART SHOWCASE COUNTERPART. Like ../videos/VideoShowcase.tsx, the Flutter
// preview never carried this screen, so it is a first port straight from the
// member app.
//
// ONE OF THE TWO SHAPES. `profile_screen.dart` chooses between the rank shape
// and `RanklessProfileBody` on the gym FLAG `selectedMember.gymRankEnabled`.
// There is no gym in this browser and therefore no flag; the rank shape is the
// one worth previewing, because it is the one carrying the two belt slots and
// the graph — the rank-less shape is the same hero with the rank block removed,
// which would preview strictly less of the theme. The `rank == null` branch
// (a member at a rank-enabled gym who has not been graded yet) is likewise
// unreachable from a constant, so it is not ported.
//
// THE HERO IS ../rewards/SparkleHero.tsx, NOT A SECOND COPY. Dart reaches the
// same widget by a different route — `ProfileStreakHero` reads the shared
// profile bloc and hands `SparkleHero` its three lines — and this island already
// has that component behind ../rewards/PointsHeadline.tsx. Same sparkle
// scatter, same clock, different copy.

import type { ShowcaseVideo } from '../showcaseContent';
import { SparkleHero } from '../rewards/SparkleHero';
import { ShowcaseBottomNav } from '../support/ShowcaseBottomNav';
import { ShowcaseScaffold } from '../support/ShowcaseScaffold';
import { ShowcaseTopbar } from '../support/ShowcaseTopbar';
import { VideoCarouselSection } from '../videos/VideoCarouselSection';
import { levelUpVideos } from '../videos/videoSelectors';

import { NextRankSection } from './NextRankSection';
import styles from './ProfileShowcase.module.css';
import { RankHeader } from './RankHeader';
import { RankProgressGraph } from './RankProgressGraph';
import {
  SHOWCASE_PROFILE_POINTS_LABEL,
  SHOWCASE_PROFILE_STREAK_WEEKS,
  SHOWCASE_RANK,
  SHOWCASE_RANK_POINTS,
} from './mockRankProgress';

/** The default every surface in this island shares. */
const DEFAULT_GYM_NAME = 'Your Gym';

/** `_kDefaultRankBadgeAsset` — the topbar's own belt tile. */
const RANK_BADGE_ASSET = 'icon_rank_belt.png' as const;

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
  // `LevelUpVideosSection` asks the portal for `videoType: educational,
  // limit: 10`; there is no portal here, so the same narrowing runs over the
  // loaded feed. It HIDES ITSELF when empty — Dart's `SizedBox.shrink()` — so a
  // tenant whose feed carries no educational videos gets no header over nothing,
  // and no divider over a section that did not render.
  const levelUp = levelUpVideos(videos);

  return (
    <ShowcaseScaffold
      horizontalPadding="none"
      bodyScroll
      bottomNav={<ShowcaseBottomNav selected="rank" />}
    >
      {/* `Column(mainAxisSize: min, stretch, spacing: spacingBig)`. */}
      <div className={styles.profile}>
        <ShowcaseTopbar
          mode="nameOnly"
          gymName={gymName}
          logoSrc={gymLogoSrc}
          streakDays={SHOWCASE_PROFILE_STREAK_WEEKS}
          pointsLabel={SHOWCASE_PROFILE_POINTS_LABEL}
          rankBadgeAsset={RANK_BADGE_ASSET}
        />

        {/* `ProfileStreakHero` — the count hero, sparkles and all. */}
        <SparkleHero
          top="YOU HAVE A"
          accent={`${String(SHOWCASE_PROFILE_STREAK_WEEKS)} WEEK`}
          bottom="STREAK"
        />

        {/* `RankSummarySection` — `Column(min, center, spacing: spacingLarge)`. */}
        <section className={styles.rankSummary}>
          <RankHeader rankTitle={SHOWCASE_RANK.name} rankSubtitle={SHOWCASE_RANK.subLabel} />
          <RankProgressGraph points={SHOWCASE_RANK_POINTS} />
        </section>

        <div className={styles.divider} />
        <NextRankSection rank={SHOWCASE_RANK} />

        {levelUp.length > 0 && (
          // `leadingDivider: true` — the rule is that the divider is drawn only
          // when the carousel itself renders, so a self-hidden section never
          // leaves a line under nothing. It is a sibling here rather than a prop
          // on the section because the gap above it is the PAGE's `spacingBig`,
          // not the section's own `spacingLarge`.
          <>
            <div className={styles.divider} />
            <VideoCarouselSection title="Videos to level up" videos={levelUp} inset="big" />
          </>
        )}
      </div>
    </ShowcaseScaffold>
  );
}
