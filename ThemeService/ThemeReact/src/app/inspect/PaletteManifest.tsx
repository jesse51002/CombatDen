// The flat palette, every key of it.
//
// The dossier above says "the engine reasons"; this says "and it emits all of
// it". So the section is deliberately the densest thing on the page — a full
// manifest, grouped by the role each token derives from, ending with the three
// surface tokens that belong to no role at all. A buyer asking "is that
// everything?" is answered by the shape of the block before they read a key.

import type { Rgba } from 'theme-react';
import { toCss } from 'theme-react';

import type { PaletteGroup } from './artifactModel';
import { hexOf, over } from './artifactModel';
import styles from './PaletteManifest.module.css';

export interface PaletteManifestProps {
  groups: readonly PaletteGroup[];
  background: Rgba;
}

export function PaletteManifest({ groups, background }: PaletteManifestProps) {
  return (
    <div className={styles.manifest}>
      {groups.map((group) => (
        <section key={group.label} className={styles.group}>
          <h3 className={styles.groupLabel}>
            {group.label}
            <span className={styles.groupCount}>{group.entries.length}</span>
          </h3>
          <ul className={styles.entries}>
            {group.entries.map((entry) => (
              <li key={entry.key} className={styles.entry}>
                <span
                  className={styles.swatch}
                  style={{ background: toCss(over(entry.color, background)) }}
                />
                <span className={styles.key}>{entry.key}</span>
                <span className={styles.hex}>{hexOf(entry.color)}</span>
              </li>
            ))}
          </ul>
        </section>
      ))}
    </div>
  );
}
