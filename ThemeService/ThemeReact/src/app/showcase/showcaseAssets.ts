// Ports ../../../../../CRM/lib/showcase/showcase_assets.dart (`ShowcaseAsset`).
//
// The showcase's bundled fallback images — the same role MobileApp's own
// bundled assets play for its real screens. The library owns NO images by
// design (`src/lib/` ships no assets), which is exactly what makes a theme a
// pure live override: the phone renders fully with the backend unreachable.
//
// Dart resolves a filename to an `AssetImage` at runtime. Vite resolves it at
// BUILD time — each import below becomes a hashed URL — so the map is keyed by
// the same filenames the Dart call sites use and the ports read one-to-one.
// Most of the PNGs are COPIES of CRM/assets/showcase/; the CRM keeps its own.
//
// `ShowcaseAsset.network` has no counterpart: Dart needs
// `CachedNetworkImageProvider` to get disk caching, and the browser's HTTP
// cache already does that for a plain `src`.
//
// THREE ASSETS BEYOND the CRM's `assets/showcase/` set:
//
//   * `combatden_logo.png`, copied from `CRM/assets/images/`.
//     `showcase_topbar.dart:97` reaches for it by that path as the LAST rung of
//     its logo ladder (below the host gym's logo and the theme's `logo_primary`
//     slot), so the ladder cannot be ported without it.
//   * `profile_rank_belt_gold.png` and `profile_next_rank_belt.png`, copied from
//     `MobileApp/assets/ranks/`. They are the bundled fallbacks under the
//     Profile screen's two belt slots (`rank_belt` and `next_rank_belt_image`)
//     — `rank_header.dart:11` and `next_rank_section.dart:9` name exactly these
//     two files. The CRM's showcase never rendered Profile, so its own asset
//     folder has neither; they come straight from the member app, which is also
//     where that screen is ported from.

import classBookedCelebration from './assets/class_booked_celebration.png';
import combatDenLogo from './assets/combatden_logo.png';
import classPhoto1 from './assets/class_photo_1.png';
import classPhoto2 from './assets/class_photo_2.png';
import classPhoto3 from './assets/class_photo_3.png';
import classPhoto4 from './assets/class_photo_4.png';
import giftbox from './assets/giftbox.png';
import gymLogoGlobalMma from './assets/gym_logo_global_mma.png';
import iconQrcode from './assets/icon_qrcode.png';
import iconRankBelt from './assets/icon_rank_belt.png';
import profileNextRankBelt from './assets/profile_next_rank_belt.png';
import profileRankBeltGold from './assets/profile_rank_belt_gold.png';
import rewardBringFriend from './assets/reward_bring_friend.png';
import rewardGloves from './assets/reward_gloves.png';
import rewardHandWraps from './assets/reward_hand_wraps.png';
import rewardMmaTshirt from './assets/reward_mma_tshirt.png';
import rewardPrivateTraining from './assets/reward_private_training.png';
import rewardPrivateTrainingShort from './assets/reward_private_training_short.png';
import singlePoint from './assets/single_point.png';
import statPointsStars from './assets/stat_points_stars.png';
import statWinsTrophy from './assets/stat_wins_trophy.png';
import streakIcon from './assets/streak_icon.png';

/**
 * Filename → built URL. The key set is a literal union, so every lookup is
 * total and `noUncheckedIndexedAccess` never widens one to `| undefined`.
 */
export const SHOWCASE_ASSETS = {
  'class_booked_celebration.png': classBookedCelebration,
  'class_photo_1.png': classPhoto1,
  'class_photo_2.png': classPhoto2,
  'class_photo_3.png': classPhoto3,
  'class_photo_4.png': classPhoto4,
  'combatden_logo.png': combatDenLogo,
  'giftbox.png': giftbox,
  'gym_logo_global_mma.png': gymLogoGlobalMma,
  'icon_qrcode.png': iconQrcode,
  'icon_rank_belt.png': iconRankBelt,
  'profile_next_rank_belt.png': profileNextRankBelt,
  'profile_rank_belt_gold.png': profileRankBeltGold,
  'reward_bring_friend.png': rewardBringFriend,
  'reward_gloves.png': rewardGloves,
  'reward_hand_wraps.png': rewardHandWraps,
  'reward_mma_tshirt.png': rewardMmaTshirt,
  'reward_private_training.png': rewardPrivateTraining,
  'reward_private_training_short.png': rewardPrivateTrainingShort,
  'single_point.png': singlePoint,
  'stat_points_stars.png': statPointsStars,
  'stat_wins_trophy.png': statWinsTrophy,
  'streak_icon.png': streakIcon,
} as const;

/** One of the bundled filenames. */
export type ShowcaseAssetFile = keyof typeof SHOWCASE_ASSETS;

/** Ports `ShowcaseAsset.image` — the built URL for a bundled filename. */
export function showcaseAsset(file: ShowcaseAssetFile): string {
  return SHOWCASE_ASSETS[file];
}

/**
 * Ports `ShowcaseAsset.imageOrNetwork`: the injected gym `url` when present,
 * otherwise the bundled `fallbackAsset`. Null / empty falls back.
 */
export function showcaseAssetOrNetwork(
  url: string | null | undefined,
  fallbackAsset: ShowcaseAssetFile,
): string {
  return url !== null && url !== undefined && url !== '' ? url : showcaseAsset(fallbackAsset);
}
