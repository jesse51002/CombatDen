// Ports ../../../../../../MobileApp/lib/features/rewards/presentation/layouts/
// rewards_bands.dart — the cost banding behind `RewardsFormat.priceLadder`.
//
// THIS IS THE FILE THE INVARIANT LIVES OR DIES ON, so it is worth being blunt
// about what it does NOT do. It reads two things, and both are already on the
// shipped points store: each reward's `pointsCost` (printed on its own card)
// and the member's `totalPoints` (the headline). It fetches nothing, derives no
// new number, and prints none — the three labels are fixed words. A band is a
// SIGNPOST, not a lock: `affordable` styles the label and nothing else, so every
// card inside stays fully legible and fully actionable.
//
// Every reward lands in exactly one band, so the ladder shows the same rewards
// the grid does, in a different order. ./__tests__/rewardsFormats.test.tsx pins
// both halves of that: the partition, and that the digits on screen are
// identical across all five arrangements.

import type { ShowcasePointsStoreItem } from './mockPointsStore';

/** `RewardBand` — one cost band and whether the member can afford it now. */
export interface RewardBand {
  readonly label: string;
  /**
   * Drives the band LABEL's colour only. See the header: a band the member has
   * not saved for yet is still a fully working row of cards.
   */
  readonly affordable: boolean;
  readonly items: readonly ShowcasePointsStoreItem[];
}

/** `'READY TO REDEEM'` — everything at or under the balance. */
export const BAND_READY = 'READY TO REDEEM';
/** `'ALMOST THERE'` — up to twice the balance. */
export const BAND_ALMOST = 'ALMOST THERE';
/** `'KEEP EARNING'` — beyond that. */
export const BAND_SAVING = 'KEEP EARNING';

/**
 * Ports `rewardBands` — bands `items` by `pointsCost`, cheapest first, against
 * the member's `totalPoints`. An empty band is dropped rather than rendered
 * with a label and nothing under it.
 *
 * The sort is a COPY: the caller's list is the store's own order and every
 * other arrangement still renders it that way.
 */
export function rewardBands(
  items: readonly ShowcasePointsStoreItem[],
  totalPoints: number,
): readonly RewardBand[] {
  const sorted = [...items].sort((a, b) => a.pointsCost - b.pointsCost);

  const ready: ShowcasePointsStoreItem[] = [];
  const almost: ShowcasePointsStoreItem[] = [];
  const saving: ShowcasePointsStoreItem[] = [];
  for (const item of sorted) {
    if (item.pointsCost <= totalPoints) ready.push(item);
    else if (item.pointsCost <= totalPoints * 2) almost.push(item);
    else saving.push(item);
  }

  const bands: RewardBand[] = [];
  if (ready.length > 0) bands.push({ label: BAND_READY, affordable: true, items: ready });
  if (almost.length > 0) bands.push({ label: BAND_ALMOST, affordable: false, items: almost });
  if (saving.length > 0) bands.push({ label: BAND_SAVING, affordable: false, items: saving });
  return bands;
}
