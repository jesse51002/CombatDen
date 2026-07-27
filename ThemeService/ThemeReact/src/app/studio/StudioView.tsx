// The generation studio — author a brief, press Launch, and watch the pipeline
// produce a theme: images appear one at a time as they finish.
//
// SCAFFOLD. This file is the routing seam's placeholder so the three parallel
// workstreams never share a file; the real view is built in place of it.
//
// It talks to a LOCAL-ONLY FastAPI app (`ThemeService/src/studio/`, :8002),
// deliberately separate from the read API on :8001 — the read API is deployed
// and boots without any provider keys, which is a property importing the
// pipeline into it would destroy. Progress arrives over server-sent events that
// replay from the first event on connect, so opening this view late still shows
// the whole run.

import styles from './StudioView.module.css';

export function StudioView() {
  return (
    <div className={styles.placeholder}>
      <p>The generation studio is being built.</p>
    </div>
  );
}
