// Ports ../../../../../CRM/lib/features/members/presentation/widgets/
// themes_library/library_card.dart.
//
// One tile in the themes library. Mirrors the CRM's canonical object-card
// pattern: panel background, 3:2 hero on top, **centered** title + category
// label underneath. The active state is a sapphire "Active" pill in the
// top-right (the same convention as the reward card's price pill).
//
// THE ONE LEGITIMATE `em` IN THIS PACKAGE lives here. Every other ported
// `letterSpacing` is an absolute Flutter pixel value and ports as `px` (see
// ../../../CLAUDE.md); this label writes `0.08 * DesignConstants.h3.fontSize`,
// which is explicitly PROPORTIONAL — so it, and only it, ports as `0.08em`.

import type { ThemeStyle } from 'theme-react';

import { CheckIcon, ImageIcon } from '../widgets/icons';

import styles from './LibraryCard.module.css';

export interface LibraryCardProps {
  style: ThemeStyle;
  isActive: boolean;
  onTap: () => void;
  /** Set on the already-selected card so the view can centre it on entry. */
  cardRef?: ((node: HTMLButtonElement | null) => void) | undefined;
}

export function LibraryCard({ style, isActive, onTap, cardRef }: LibraryCardProps) {
  const category = (style.category ?? '').trim();
  return (
    <button ref={cardRef} type="button" className={styles.card} onClick={onTap}>
      <Hero imageUrl={style.celebrationImageUrl} />
      <span className={styles.body}>
        {/* A fixed band, so a one-line and a two-line title card measure the
            same (`DesignConstants.rewardCardTitleHeight`). */}
        <span className={styles.titleBand}>
          <span className={styles.title}>{style.displayName}</span>
        </span>
        {category !== '' && <span className={styles.category}>{category.toUpperCase()}</span>}
      </span>
      {isActive && (
        <span className={styles.activePill}>
          <CheckIcon size={18} />
          Active
        </span>
      )}
    </button>
  );
}

function Hero({ imageUrl }: { imageUrl: string }) {
  return (
    <span className={styles.hero}>
      <ImageIcon className={styles.heroPlaceholder} size={32} />
      {imageUrl !== '' && (
        <img
          key={imageUrl}
          className={styles.heroImage}
          src={imageUrl}
          alt=""
          loading="lazy"
          // `errorBuilder` — drop the <img> and leave the placeholder showing.
          onError={(event) => {
            event.currentTarget.style.visibility = 'hidden';
          }}
        />
      )}
    </span>
  );
}
