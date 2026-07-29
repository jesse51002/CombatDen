// The React glue over ../data/showcaseDefaults.ts, and the resolution ladder
// from ../../../../../CRM/lib/features/members/presentation/widgets/member_app/
// theme_tab/theme_preview_pane.dart:179-195.
//
// The ladder, verbatim: the selected gym's REAL content wins; failing that the
// FETCHED demo content for the previewed theme's category; failing that the
// BUNDLED offline constants. A single real item is then repeated across all
// four slots (`fillSlots`). In this public browser the real branch is always
// absent — there is no gym — so the fetch and the bundle are what actually
// render, and the phone is complete with the backend down.
//
// The defaults live in a MODULE STORE read through `useSyncExternalStore`,
// exactly as the library's own theme store is: one fetch shared by every mount,
// a cached snapshot reference (a fresh literal per call makes
// `useSyncExternalStore` throw and loop — see ../../CLAUDE.md), and no
// `setState` anywhere, which the React Compiler's `set-state-in-effect` rule
// makes a hard requirement here.

import { useEffect, useSyncExternalStore } from 'react';

import type { ShowcaseDefaults } from '../data/showcaseDefaults';
import { EMPTY_SHOWCASE_DEFAULTS, loadShowcaseDefaults, showcaseDefaultsFor } from '../data/showcaseDefaults';

import type { ShowcaseClassInfo, ShowcaseReward, ShowcaseVideo } from './showcaseContent';
import { fillSlots } from './showcaseContent';
import { bundledClasses, bundledRewards, showcaseGroupFor } from './showcaseGroupDefaults';
import { bundledVideos } from './showcaseVideoDefaults';

let current: ShowcaseDefaults = EMPTY_SHOWCASE_DEFAULTS;
let inFlight = false;
const listeners = new Set<() => void>();

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

/** The cached reference. Never a fresh object — see the header. */
function getSnapshot(): ShowcaseDefaults {
  return current;
}

/**
 * Kicks the one fetch. Not latched on failure: `loadShowcaseDefaults` clears
 * its own memo when it fails, so the next mount genuinely re-attempts rather
 * than pinning the empty answer for the session.
 */
function ensureLoaded(): void {
  if (inFlight) return;
  inFlight = true;
  void loadShowcaseDefaults().then((value) => {
    inFlight = false;
    if (value === current) return;
    current = value;
    for (const listener of [...listeners]) listener();
  });
}

/** The fetched demo content, empty until (and unless) the read lands. */
export function useShowcaseDefaults(): ShowcaseDefaults {
  const defaults = useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
  useEffect(() => {
    ensureLoaded();
  }, []);
  return defaults;
}

/** What the phone renders: four class cards, four reward cards, and a video feed. */
export interface ShowcaseContent {
  readonly classes: readonly ShowcaseClassInfo[];
  readonly rewards: readonly ShowcaseReward[];
  readonly videos: readonly ShowcaseVideo[];
}

/**
 * The resolved content for `category` (`Fighting`, `Yoga`, … — the previewed
 * style's own bucket; null falls back to the default group).
 *
 * `realClasses` / `realRewards` / `realVideos` are the selected gym's own
 * content. They are always absent in this browser and are kept on the signature
 * because `fillSlots` is the shared rule: an admin host that DOES have a gym
 * passes them, and one real item then fills all four cards.
 *
 * VIDEOS DO NOT GO THROUGH `fillSlots`, and that is deliberate rather than an
 * omission. `fillSlots` exists because the schedule and the store are FIXED
 * FOUR-CARD layouts that a one-class gym would otherwise leave three-quarters
 * empty. A feed has no slots — it is however long it is — so repeating a single
 * video fourteen times would invent a feed rather than fill a layout, and the
 * genre carousels would all hold the same card. An empty real feed simply falls
 * through to the bundled one, which is the same rule minus the repeat.
 *
 * The FETCHED tier has no video branch either: `GET /theme/showcase-defaults`
 * serves `{classes, rewards}` only (`FastApiBackend/src/theme/schema/
 * theme_schema.py`), so a video feed resolves real → bundled with nothing in
 * between. Wiring a third tier the wire format cannot fill would be a branch
 * that is dead by construction.
 */
export function useShowcaseContent(
  category: string | null,
  realClasses?: readonly ShowcaseClassInfo[] | null,
  realRewards?: readonly ShowcaseReward[] | null,
  realVideos?: readonly ShowcaseVideo[] | null,
): ShowcaseContent {
  const defaults = useShowcaseDefaults();
  // `selectedGym.themeCategory ?? showcaseGroupFor(selectedGym.videoGymId)` —
  // and `showcaseGroupFor(null)` is the default group, so the key handed to the
  // FETCHED map is never null. Resolving it here rather than leaning on
  // `bundledClasses`'s own default is what keeps the fetch reachable: a null
  // key would miss every fetched bucket and silently pin the phone to the
  // offline constants even with the backend up.
  const key = category ?? showcaseGroupFor(null);
  const fetched = showcaseDefaultsFor(defaults, key);
  return {
    classes: fillSlots(realClasses, fetched?.classes ?? bundledClasses(key)),
    rewards: fillSlots(realRewards, fetched?.rewards ?? bundledRewards(key)),
    videos:
      realVideos === null || realVideos === undefined || realVideos.length === 0
        ? bundledVideos(key)
        : realVideos,
  };
}
