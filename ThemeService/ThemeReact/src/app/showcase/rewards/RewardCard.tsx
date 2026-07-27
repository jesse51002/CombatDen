// Ports ../../../../../../CRM/lib/showcase/rewards/reward_card.dart — a clone
// of MobileApp's shared reward card: a 3:2 photo with a brand-coloured price
// tag pinned top-right, then a fixed-height title slot, the points cost, and a
// full-width CTA.
//
// The photo is the injected gym URL when the host supplied one, else the
// bundled sample (`ShowcaseAsset.imageOrNetwork`). A network photo that fails
// to load degrades to a flat `card` rectangle rather than a broken-image box —
// Dart's `errorBuilder`, and the same reset ../home/ClassListItem.tsx uses.
//
// FOUR PUBLIC WIDGETS THERE, ONE HERE. Dart also exports `RewardImageHero`,
// `RewardPriceTag` and `RewardPointsCost` because its kiosk and its My-Rewards
// list reuse them; this island has neither surface, so they stay private
// helpers rather than an export surface nothing imports. `formatRewardPoints`
// is likewise the island's single ../formatPoints.ts.
//
// NO TAP CALLBACK. Dart requires `onPressed` and the store passes an empty
// closure; every showcase surface is a preview that takes no input, so the port
// leans on ../support/ShowcasePrimaryButton.tsx's own no-op default.

import { useState } from 'react';

import { formatThousands } from '../formatPoints';
import { showcaseAssetOrNetwork } from '../showcaseAssets';
import { ShowcasePrimaryButton } from '../support/ShowcasePrimaryButton';

import type { ShowcasePointsStoreItem } from './mockPointsStore';
import styles from './RewardCard.module.css';

export interface RewardCardProps {
  item: ShowcasePointsStoreItem;
  /** `RewardCard.buttonText` — the CTA's label ("Redeem", "Use"). */
  buttonText: string;
}

export function RewardCard({ item, buttonText }: RewardCardProps) {
  return (
    // `Container(color: card, borderRadius: radiusBig, clipBehavior: antiAlias)`.
    <div className={styles.card}>
      <RewardImageHero item={item} />
      {/* `Padding(paddingSmall) > Column(stretch, spacing: spacingMedium)`. */}
      <div className={styles.body}>
        {/*
          `SizedBox(height: 42) > Align(topCenter) > Text(maxLines: 2, ellipsis)`.
          Two lines of `h2` are reserved whether the title needs one or two, so
          every card in a column lines up.
        */}
        <div className={styles.titleSlot}>
          <span className={styles.title}>{item.title}</span>
        </div>
        <span className={styles.points}>{formatThousands(item.pointsCost)} pts</span>
        <ShowcasePrimaryButton text={buttonText} fullWidth />
      </div>
    </div>
  );
}

/** `RewardImageHero` — `AspectRatio(1.5) > Stack(expand)`. */
function RewardImageHero({ item }: { item: ShowcasePointsStoreItem }) {
  const src = showcaseAssetOrNetwork(item.imageUrl, item.imageAsset ?? 'reward_bring_friend.png');
  return (
    <div className={styles.hero}>
      {/*
        `key` remounts the frame whenever the photo changes — a category switch
        swaps the whole store, and without the reset one dead URL would pin this
        slot to the empty box forever. Resetting in an effect is a lint error in
        this package (see ../../../CLAUDE.md).
      */}
      <RewardPhoto key={src} src={src} alt={item.title} />
      {/* `Positioned(top: spacingMedium, right: spacingMedium)`. */}
      <span className={styles.priceTag}>{item.priceLabel}</span>
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
