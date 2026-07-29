// One colour role, at the scale a colour deserves: the value as a field, the
// name and the pipeline's written purpose beside it, and its seven derivations
// as a ladder underneath.
//
// The description is why this component exists. `ThemeColorValue.description`
// is parsed by the runtime and rendered NOWHERE else in either client — the
// phone preview draws the colour and throws the sentence away. It is the only
// artifact on the wire that explains the engine's own reasoning, so here it is
// body copy at reading measure, not a tooltip.
//
// The field carries a live contrast readout because `regular_text` is a claim:
// the pipeline computes it as "body text if it clears WCAG AA on this fill,
// else whichever of text/background contrasts better". Printing the measured
// ratio beside a label actually painted in it is the difference between showing
// a buyer the claim and showing them the check.

import type { Rgba } from 'theme-react';
import { fontStack, toCss } from 'theme-react';

import type { RoleView } from './artifactModel';
import { contrastRatio, hexOf, over, readableInk } from './artifactModel';
import styles from './ColorRole.module.css';

export interface ColorRoleProps {
  role: RoleView;
  /** The theme's own ground — what every translucent value is drawn over. */
  background: Rgba;
  /** The theme's display face. Pipeline-authored names are set in it. */
  displayFont: string;
  /** The theme's body face. Pipeline-authored prose is set in it. */
  bodyFont: string;
}

export function ColorRole({ role, background, displayFont, bodyFont }: ColorRoleProps) {
  return (
    <article className={styles.role}>
      <RoleField role={role} />
      <div className={styles.text}>
        <h3 className={styles.name} style={{ fontFamily: fontStack(displayFont) }}>
          {role.displayName === '' ? role.slot : role.displayName}
        </h3>
        <p className={styles.slot}>{role.slot}</p>
        {role.description === '' ? (
          <p className={styles.noProse}>No description was produced for this role.</p>
        ) : (
          <p className={styles.description} style={{ fontFamily: fontStack(bodyFont) }}>
            {role.description}
          </p>
        )}
      </div>
      <ol className={styles.ladder}>
        {role.derivations.map((derivation) => (
          <li key={derivation.key} className={styles.rung}>
            <div
              className={derivation.color === null ? styles.chipEmpty : styles.chip}
              style={
                derivation.color === null
                  ? undefined
                  : { background: toCss(over(derivation.color, background)) }
              }
            />
            <p className={styles.rungKey}>{derivation.key}</p>
            <p className={styles.rungHex}>
              {derivation.color === null ? 'not produced' : hexOf(derivation.color)}
            </p>
          </li>
        ))}
      </ol>
    </article>
  );
}

function RoleField({ role }: { role: RoleView }) {
  if (role.color === null) {
    return (
      <div className={styles.fieldEmpty}>
        <p className={styles.fieldMissing}>not produced</p>
      </div>
    );
  }
  const ink = toCss(readableInk(role.color));
  return (
    <div className={styles.field} style={{ background: toCss(role.color) }}>
      <p className={styles.fieldValue} style={{ color: ink }}>
        {hexOf(role.color)}
      </p>
      {role.onColor === null ? null : (
        <div className={styles.fieldProof}>
          {/*
            The sample is painted in the derivation it names, so it IS the
            evidence rather than a claim about it — and the measurement beside
            it is painted in the guaranteed-readable ink, so a theme whose
            `regular_text` turned out marginal still reports its own number
            legibly instead of hiding the bad news in an unreadable label.
          */}
          <p className={styles.fieldSample} style={{ color: toCss(role.onColor) }}>
            Aa regular_text
          </p>
          <p className={styles.fieldRatio} style={{ color: ink }}>
            {contrastRatio(role.onColor, role.color).toFixed(1)}:1
          </p>
        </div>
      )}
    </div>
  );
}
