// Ports ../../../../../../MobileApp/lib/features/rewards/presentation/widgets/
// reward_card/{reward_card.dart,reward_card_data.dart,layouts/*.dart} — the
// shared reward card and its five ARRANGEMENTS.
//
// PRESENTATION ONLY, AND THAT IS THE WHOLE POINT. Every value of `layout`
// renders the identical element set from the identical item: the image, exactly
// one price tag, the title, the points cost, and exactly ONE redeem action that
// belongs to this card. A value may move them and change their prominence. It
// may not drop one, add one, or hand one to somebody else — including the
// screen arrangement that placed the card.
// ./__tests__/rewardsFormats.test.tsx counts them per card, per screen format.
//
// `imageTop` is what ships and reproduces the previous single-arrangement card
// value for value, which is why that test also freezes ./StoreGrid.tsx's markup.
//
// NO TAP CALLBACK, AND NO REDEEM DIALOG. Dart's `RewardStoreCard` wires every
// card's action to `RewardRedeemDialog`; every showcase surface is a preview
// inside a phone frame that takes no input, so the port leans on
// ../support/ShowcasePrimaryButton.tsx's own no-op default. The action is still
// exactly one <button> per card — which is what the gate counts.

import type { ReactElement } from 'react';

import { cx } from '../cx';
import { ShowcasePrimaryButton } from '../support/ShowcasePrimaryButton';

import type { ShowcasePointsStoreItem } from './mockPointsStore';
import styles from './RewardCard.module.css';
import { RewardImageHero, RewardPointsCost, RewardPriceTag, RewardTitle } from './rewardCardParts';

/**
 * `RewardCardLayout` — how a reward card is arranged.
 *
 *   * `imageTop`  — image on top, title / cost / action stacked. Ships today.
 *   * `thumbLeft` — full-width row: square thumb leading, action trailing.
 *   * `poster`    — tall single-focus poster; the image takes the height it is given.
 *   * `tile`      — dense square tile for a multi-column band.
 *   * `hero`      — full-bleed promoted card; text and action ride the image.
 */
export type RewardCardLayout = 'imageTop' | 'thumbLeft' | 'poster' | 'tile' | 'hero';

export interface RewardCardProps {
  item: ShowcasePointsStoreItem;
  /** `RewardCard.buttonText` — the CTA's label ("Redeem", "Use"). */
  buttonText: string;
  layout?: RewardCardLayout | undefined;
}

export function RewardCard({ item, buttonText, layout = 'imageTop' }: RewardCardProps) {
  // A switch rather than a ternary chain at five cases, and exhaustive over the
  // union — a new arrangement fails to typecheck here until it is built.
  let card: ReactElement;
  switch (layout) {
    case 'imageTop':
      card = <RewardCardImageTop item={item} buttonText={buttonText} />;
      break;
    case 'thumbLeft':
      card = <RewardCardThumbLeft item={item} buttonText={buttonText} />;
      break;
    case 'poster':
      card = <RewardCardPoster item={item} buttonText={buttonText} />;
      break;
    case 'tile':
      card = <RewardCardTile item={item} buttonText={buttonText} />;
      break;
    case 'hero':
      card = <RewardCardHero item={item} buttonText={buttonText} />;
      break;
  }
  return card;
}

interface ArrangementProps {
  item: ShowcasePointsStoreItem;
  buttonText: string;
}

/**
 * `RewardCardLayout.imageTop` — the card that ships today.
 *
 * `Container(color: card, borderRadius: radiusBig, clipBehavior: antiAlias)`;
 * the clip is what rounds the photo's top corners. 3:2 image with the price tag
 * pinned top-right, then a fixed-height title slot, the cost, and a full-width
 * action.
 */
function RewardCardImageTop({ item, buttonText }: ArrangementProps) {
  return (
    <div className={styles.shell} data-reward-card="imageTop">
      <RewardImageHero item={item} />
      {/* `Padding(paddingSmall) > Column(min, stretch, spacing: spacingMedium)`. */}
      <div className={styles.body}>
        <RewardTitle title={item.title} maxLines={2} reserveTwoLines />
        <RewardPointsCost pointsCost={item.pointsCost} />
        <ShowcasePrimaryButton text={buttonText} fullWidth />
      </div>
    </div>
  );
}

/**
 * `RewardCardLayout.thumbLeft` — a full-width row.
 *
 * Square thumb leading, title over an inline price tag + cost, action trailing,
 * hairline rule beneath. Scans faster than a grid when titles are long, which
 * is the case the two-line clamp papers over — so the title takes the full
 * width and the clamp stops deciding what a reward is called.
 */
function RewardCardThumbLeft({ item, buttonText }: ArrangementProps) {
  return (
    // `Container(padding: symmetric(vertical: spacingLarge),
    // border: Border(bottom: divider @ dividerThickness))`.
    <div className={styles.row} data-reward-card="thumbLeft">
      {/* `SizedBox(width: 76)` — an asset-bound dimension, not a spacing token. */}
      <div className={styles.thumb}>
        <RewardImageHero item={item} fit="square" showPriceTag={false} rounded />
      </div>
      {/* `Expanded(child: _RowMeta)` — `Column(start, spacing: spacingSmall)`. */}
      <div className={styles.rowMeta}>
        <RewardTitle title={item.title} maxLines={1} align="left" />
        {/* `Row(mainAxisSize: min, spacing: spacingMedium)` — the tag moves inline. */}
        <div className={styles.rowInline}>
          <RewardPriceTag label={item.priceLabel} />
          <RewardPointsCost pointsCost={item.pointsCost} variant="h3" align="left" />
        </div>
      </div>
      <ShowcasePrimaryButton text={buttonText} />
    </div>
  );
}

/**
 * `RewardCardLayout.poster` — one reward, given the whole deck.
 *
 * THE ACTION STAYS INSIDE THE POSTER. Lifting it out to a single pinned button
 * under the deck would leave the card without the one element the reward-card
 * contract says it carries, and would make the button ambiguous mid-swipe —
 * halfway between two posters it belongs to neither.
 */
function RewardCardPoster({ item, buttonText }: ArrangementProps) {
  return (
    <div className={cx(styles.shell, styles.poster)} data-reward-card="poster">
      <RewardImageHero item={item} fit="flex" />
      <div className={styles.body}>
        <RewardTitle title={item.title} maxLines={2} reserveTwoLines />
        <RewardPointsCost pointsCost={item.pointsCost} variant="h1" />
        <ShowcasePrimaryButton text={buttonText} fullWidth />
      </div>
    </div>
  );
}

/**
 * `RewardCardLayout.tile` — the dense square used inside a cost band, three to
 * a row: square image with the tag in its corner, one line of title, a small
 * cost, and a small full-width action.
 *
 * The button's overrides are CSS STRINGS rather than resolved values, which is
 * how ../support/ShowcasePrimaryButton.tsx keeps a call site inside the token
 * system (`textStyle: pSmall`, `padding: all(spacingSmall)` in the Dart).
 */
function RewardCardTile({ item, buttonText }: ArrangementProps) {
  return (
    <div className={styles.shell} data-reward-card="tile">
      <RewardImageHero item={item} fit="square" />
      {/* `Padding(spacingMedium) > Column(min, stretch, spacing: spacingSmall)`. */}
      <div className={styles.tileBody}>
        <RewardTitle title={item.title} maxLines={1} variant="p" />
        <RewardPointsCost pointsCost={item.pointsCost} variant="pSmall" />
        <ShowcasePrimaryButton
          text={buttonText}
          fullWidth
          font="var(--sc-type-p-small)"
          letterSpacing="var(--sc-type-p-small-ls)"
          padding="var(--sc-spacing-small)"
        />
      </div>
    </div>
  );
}

/**
 * `RewardCardLayout.hero` — the promoted reward, full bleed.
 *
 * The image runs edge to edge with the price tag in its corner; title, cost and
 * action ride the bottom of the image over a scrim. Same five elements as every
 * other arrangement, stacked instead of listed.
 */
function RewardCardHero({ item, buttonText }: ArrangementProps) {
  return (
    // `AspectRatio(16 / 9) > Stack(fit: expand)`.
    <div className={styles.hero} data-reward-card="hero">
      <RewardImageHero item={item} fit="absolute" />
      {/* `_HeroScrim` — keeps the overlaid text legible over any photograph. */}
      <div className={styles.heroScrim} aria-hidden="true" />
      {/* `Positioned(left/right/bottom: 0) > Padding(paddingSmall) > Column`. */}
      <div className={styles.heroBody}>
        <RewardTitle title={item.title} maxLines={1} variant="h1" />
        <RewardPointsCost pointsCost={item.pointsCost} />
        <ShowcasePrimaryButton text={buttonText} fullWidth />
      </div>
    </div>
  );
}
