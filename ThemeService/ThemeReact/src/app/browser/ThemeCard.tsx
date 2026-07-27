// Ports ../../../../../CRM/lib/features/members/presentation/widgets/
// member_app/theme_tab/theme_card.dart.
//
// A compact, tappable theme row: a small celebration thumbnail, the theme name,
// and a check when active. Tapping switches the LIVE preview theme through the
// customization engine, so the phone re-themes instantly.
//
// DEVIATION: the active border is drawn as a TRANSPARENT 3px border when
// inactive rather than no border at all. Flutter's `Border.all` grows the box
// by its width, so the Dart row visibly jumps 3px when it becomes active;
// reserving the stroke keeps the list still.

import type { ThemeStyle } from 'theme-react';

import { CheckCircleIcon, ImageIcon } from '../widgets/icons';
import { cx } from '../widgets/cx';

import { selectedStyle } from './selectedStyle';
import styles from './ThemeCard.module.css';

export interface ThemeCardProps {
  style: ThemeStyle;
  isActive: boolean;
}

export function ThemeCard({ style, isActive }: ThemeCardProps) {
  return (
    <button
      type="button"
      className={cx(styles.card, isActive && styles.active)}
      aria-pressed={isActive}
      // Records the previewed design + its category globally and brands the
      // live preview with it (theme-only — decoupled from any content gym).
      onClick={() => selectedStyle.selectStyle(style)}
    >
      <Thumb imageUrl={style.celebrationImageUrl} />
      <span className={styles.name}>{style.displayName}</span>
      {isActive && <CheckCircleIcon className={styles.check} size={20} />}
    </button>
  );
}

function Thumb({ imageUrl }: { imageUrl: string }) {
  return (
    <span className={styles.thumb}>
      <ImageIcon className={styles.thumbPlaceholder} size={20} />
      {imageUrl !== '' && (
        // `key` remounts on a URL change so a previously-failed image is
        // retried rather than staying hidden — the same reason theme-react's
        // <ThemedImage> keys its frame.
        <img
          key={imageUrl}
          className={styles.thumbImage}
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
