// Ports ../../../../../../MobileApp/lib/features/rewards/presentation/widgets/
// reward_card/parts/*.dart — the elements EVERY reward card carries, in every
// arrangement: the image, the price tag, the title and the points cost. The
// fifth, the one redeem action, is ../support/ShowcasePrimaryButton.tsx.
//
// WHY THE PARTS ARE THEIR OWN MODULE. `rewards_format` gives the points store
// five arrangements and the card five of its own, and the parts are what stays
// identical across all of them. Splitting them out is what makes "an
// arrangement rearranges, it never adds or drops" a property of the code rather
// than a promise: every arrangement in ./RewardCard.tsx composes exactly these,
// and ./__tests__/rewardsFormats.test.tsx counts them per card, per format.
//
// `data-reward-part` is the DOM's answer to Dart's `find.byType(RewardPriceTag)`.
// The Flutter invariant test counts WIDGET TYPES; the DOM has no types, so each
// part names itself and the census reads the attribute. It is markup for the
// gate, not styling — no stylesheet selects on it.
//
// The knobs below are PRESENTATION, exactly as they are in Dart. `showPriceTag:
// false` means the CALLER renders the one tag (the row layout puts it inline
// beside the cost); it never means a card loses its tag.

import { useState } from 'react';

import { cx } from '../cx';
import { formatThousands } from '../formatPoints';
import { showcaseAssetOrNetwork } from '../showcaseAssets';

import type { ShowcasePointsStoreItem } from './mockPointsStore';
import styles from './rewardCardParts.module.css';

/** The `data-reward-part` names. The action is a `<button>` and needs none. */
export const REWARD_PART = Object.freeze({
  image: 'image',
  priceTag: 'price-tag',
  title: 'title',
  cost: 'cost',
});

/**
 * `RewardImageHero.aspectRatio`, as the four shapes the arrangements ask for:
 *
 *   * `ratio32` — `kRewardImageRatio` (1.5). The shipped 3:2.
 *   * `square` — the band tile and the row's thumb.
 *   * `flex` — `aspectRatio: null` inside a COLUMN: the poster's image takes
 *     every pixel the deck's height leaves after the title, cost and action.
 *   * `absolute` — `aspectRatio: null` inside a STACK: the hero's image fills
 *     the 16:9 box its card already pins.
 */
export type RewardImageFit = 'ratio32' | 'square' | 'flex' | 'absolute';

function fitClass(fit: RewardImageFit): string | undefined {
  if (fit === 'ratio32') return styles.ratio32;
  if (fit === 'square') return styles.square;
  if (fit === 'flex') return styles.flexFill;
  return styles.absoluteFill;
}

export interface RewardImageHeroProps {
  item: ShowcasePointsStoreItem;
  fit?: RewardImageFit | undefined;
  /** `showPriceTag` — false hands the one tag to the caller. See the header. */
  showPriceTag?: boolean | undefined;
  /** `borderRadius` — rounds the image itself, for a layout outside a card clip. */
  rounded?: boolean | undefined;
}

/** `RewardImageHero` — `AspectRatio > Stack(expand)`. */
export function RewardImageHero({
  item,
  fit = 'ratio32',
  showPriceTag = true,
  rounded = false,
}: RewardImageHeroProps) {
  const src = showcaseAssetOrNetwork(item.imageUrl, item.imageAsset ?? 'reward_bring_friend.png');
  return (
    <div
      className={cx(styles.imageHero, fitClass(fit), rounded && styles.rounded)}
      data-reward-part={REWARD_PART.image}
    >
      {/*
        `key` remounts the frame whenever the photo changes — a category switch
        swaps the whole store, and without the reset one dead URL would pin this
        slot to the empty box forever. Resetting in an effect is a lint error in
        this package (see ../../../CLAUDE.md).
      */}
      <RewardPhoto key={src} src={src} alt={item.title} />
      {showPriceTag && <RewardPriceTag label={item.priceLabel} />}
    </div>
  );
}

/** `Image(fit: BoxFit.cover, errorBuilder: ColoredBox(card))`. */
function RewardPhoto({ src, alt }: { src: string; alt: string }) {
  const [failed, setFailed] = useState(false);
  if (failed) return null;
  return (
    <img
      className={styles.photo}
      src={src}
      alt={alt}
      onError={() => {
        setFailed(true);
      }}
    />
  );
}

/**
 * `RewardPriceTag` — the brand-coloured chip a reward carries ("Free",
 * "30% off"). Exactly one per card in every arrangement; WHERE it sits changes
 * (over the image corner, or inline beside the cost), that it exists does not.
 *
 * Nothing here positions it: inside ./rewardCardParts.module.css's `.imageHero`
 * a descendant rule pins it to the top-right corner, and everywhere else it is
 * an ordinary inline chip — which is the difference between Dart's `Positioned`
 * wrapper and its bare `Flexible` one.
 */
export function RewardPriceTag({ label }: { label: string }) {
  return (
    <span className={styles.priceTag} data-reward-part={REWARD_PART.priceTag}>
      {label}
    </span>
  );
}

/** `RewardTitle.style` — the type rung the arrangement gives the title. */
export type RewardTitleVariant = 'h1' | 'h2' | 'p';

export interface RewardTitleProps {
  title: string;
  /** `Text.maxLines`. */
  maxLines: 1 | 2;
  variant?: RewardTitleVariant | undefined;
  align?: 'center' | 'left' | undefined;
  /**
   * `reserveHeight: kRewardTitleTwoLine` — two lines of 16px `h2` at ~1.3,
   * held open so a one-line and a two-line title produce the same card height.
   * The 42 is the Dart's own const; it is a fixed box, not a derivation.
   */
  reserveTwoLines?: boolean | undefined;
}

/** `RewardTitle`. */
export function RewardTitle({
  title,
  maxLines,
  variant = 'h2',
  align = 'center',
  reserveTwoLines = false,
}: RewardTitleProps) {
  const text = (
    <span
      className={cx(
        styles.title,
        variant === 'h1' ? styles.titleH1 : variant === 'p' ? styles.titleP : styles.titleH2,
        maxLines === 1 ? styles.clamp1 : styles.clamp2,
        align === 'left' ? styles.alignLeft : styles.alignCenter,
      )}
      data-reward-part={REWARD_PART.title}
    >
      {title}
    </span>
  );
  if (!reserveTwoLines) return text;
  // `SizedBox(height: 42) > Align(topCenter)`.
  return <div className={styles.titleSlot}>{text}</div>;
}

/** `RewardPointsCost.style` — the type rung the arrangement gives the cost. */
export type RewardCostVariant = 'h1' | 'h2' | 'h3' | 'pSmall';

function costClass(variant: RewardCostVariant): string | undefined {
  if (variant === 'h1') return styles.costH1;
  if (variant === 'h3') return styles.costH3;
  if (variant === 'pSmall') return styles.costPSmall;
  return styles.costH2;
}

export interface RewardPointsCostProps {
  pointsCost: number;
  variant?: RewardCostVariant | undefined;
  align?: 'center' | 'left' | undefined;
}

/** `RewardPointsCost` — `Text('… pts')`. Exactly one per card. */
export function RewardPointsCost({
  pointsCost,
  variant = 'h2',
  align = 'center',
}: RewardPointsCostProps) {
  return (
    <span
      className={cx(
        styles.cost,
        costClass(variant),
        align === 'left' ? styles.alignLeft : styles.alignCenter,
      )}
      data-reward-part={REWARD_PART.cost}
    >
      {formatThousands(pointsCost)} pts
    </span>
  );
}
