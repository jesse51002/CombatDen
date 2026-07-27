// The artifact inspector — every value the pipeline generated for one theme,
// shown at once: the four colour roles with all seven derivations each, the ten
// images, both fonts, the five texts, the four icons.
//
// SCAFFOLD. This file is the routing seam's placeholder so the three parallel
// workstreams never share a file; the real view is built in place of it.
//
// Nothing new is needed from the runtime to build it: `useThemeConfig()` already
// returns the whole resolved `ThemeConfig`, and each entry in its `colors` map
// is a `ThemeColorValue` carrying `displayName` ("Red Corner") and a written
// `description` of that colour's purpose — both parsed today and rendered
// nowhere.

import styles from './InspectView.module.css';

export function InspectView() {
  return (
    <div className={styles.placeholder}>
      <p>The artifact inspector is being built.</p>
    </div>
  );
}
