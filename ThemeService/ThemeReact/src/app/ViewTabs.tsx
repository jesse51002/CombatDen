// SCAFFOLD — the temporary way to reach the three top-level views.
//
// Deliberately its own file, importing nothing but the view union, so the
// designed navigation replaces it with a delete rather than an untangle. It is
// intentionally plain: shipping a half-considered nav bar would put undesigned
// chrome above every screen in the demo, so this stays visibly provisional
// until the design pass lands.
//
// Routing does NOT depend on it — every view is reachable by URL (`?view=`,
// ../appUrl.ts), which is what the parallel workstreams build against.

import type { AppView } from './appUrl';
import styles from './ViewTabs.module.css';

const TABS: readonly { readonly view: AppView; readonly label: string }[] = Object.freeze([
  { view: 'browse', label: 'Library' },
  { view: 'inspect', label: 'Inspect' },
  { view: 'studio', label: 'Studio' },
]);

export function ViewTabs({
  view,
  onChange,
}: {
  view: AppView;
  onChange: (next: AppView) => void;
}) {
  return (
    <nav className={styles.tabs} aria-label="View">
      {TABS.map((tab) => (
        <button
          key={tab.view}
          type="button"
          className={styles.tab}
          aria-current={tab.view === view ? 'page' : undefined}
          onClick={() => onChange(tab.view)}
        >
          {tab.label}
        </button>
      ))}
    </nav>
  );
}
