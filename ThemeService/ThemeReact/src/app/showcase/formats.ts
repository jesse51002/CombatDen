// The layout format vocabulary, and how a screen resolves the one it renders.
//
// Ports ../../../../../MobileApp/lib/core/formats/{layout_formats,format_store,
// format_parse}.dart — the enums, the override store the dev picker writes, and
// the parse-with-fallback.
//
// WHY THE VALUE NAMES ARE COPIED RATHER THAN DERIVED: they are the WIRE. The
// pipeline classifies a run into these exact strings (`ThemeService/apps/
// combatden/app.yaml`), the member app parses them back with `fromWire`, and a
// typo does not raise anywhere — it silently reads as "the classifier chose the
// default", forever. So they are transcribed value-for-value and the first of
// each list is the arrangement that ships today, which is also the fallback.
//
// THE INVARIANT EVERY ARRANGEMENT HOLDS: a format changes ARRANGEMENT ONLY. No
// screen is merged or split, no functionality is added, none is removed, and no
// variant reaches data the shipped screen did not already have. That is what
// makes the whole idea sellable — the app a member gets is rearranged, never
// reduced — so it is a correctness property, not a style note.

import { useCallback, useSyncExternalStore } from 'react';
import { useThemeConfig } from 'theme-react';

export const APP_SHELL_FORMATS = ['stacked', 'compactRail', 'statFirst', 'markOnly'] as const;
export const HOME_FORMATS = [
  'agendaList',
  'dayPager',
  'timeSpine',
  'nextUpHero',
  'boardGrid',
] as const;
export const VIDEOS_FORMATS = [
  'carouselRows',
  'editorialStack',
  'mosaic',
  'shortsColumn',
  'tagRail',
] as const;
export const RANK_FORMATS = [
  'sparkleStack',
  'beltHero',
  'statTiles',
  'progressFirst',
  'splitRank',
] as const;
export const REWARDS_FORMATS = [
  'cardGrid',
  'listRows',
  'posterDeck',
  'priceLadder',
  'storefrontHero',
] as const;
export const CLASS_FORMATS = [
  'bannerStack',
  'overlayHero',
  'detailSheet',
  'sectionTabs',
  'specBrief',
] as const;
export const CELEBRATION_FORMATS = [
  'centerHero',
  'figureTop',
  'cardReveal',
  'splitBand',
  'fullBleed',
] as const;

export type AppShellFormat = (typeof APP_SHELL_FORMATS)[number];
export type HomeFormat = (typeof HOME_FORMATS)[number];
export type VideosFormat = (typeof VIDEOS_FORMATS)[number];
export type RankFormat = (typeof RANK_FORMATS)[number];
export type RewardsFormat = (typeof REWARDS_FORMATS)[number];
export type ClassFormat = (typeof CLASS_FORMATS)[number];
export type CelebrationFormat = (typeof CELEBRATION_FORMATS)[number];

/** The `app.yaml` slot id each vocabulary is classified into. */
export const FORMAT_SLOTS = Object.freeze({
  appShell: 'app_shell_format',
  home: 'home_format',
  videos: 'videos_format',
  rank: 'rank_format',
  rewards: 'rewards_format',
  class: 'class_format',
  celebration: 'celebration_format',
});

/**
 * The preview's override store — the analogue of Dart's `FormatStore`, and the
 * reason it exists is the same: reviewing an arrangement should not cost a
 * reload, and switching one must not throw you off the screen you are judging.
 *
 * In-memory only. This is a preview surface; nothing here is persisted and
 * nothing a tenant sees resolves through it.
 */
const overrides = new Map<string, string>();
const listeners = new Set<() => void>();

/**
 * `useSyncExternalStore` throws and loops if `getSnapshot` returns a fresh
 * value each call, so the snapshot is a counter bumped on write rather than a
 * rebuilt object (see ../../CLAUDE.md, "Things that will bite").
 */
let version = 0;

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

function getVersion(): number {
  return version;
}

/** Pin `slot` to `value`; pass `null` to release it back to the theme's pick. */
export function setFormatOverride(slot: string, value: string | null): void {
  if (value === null) overrides.delete(slot);
  else overrides.set(slot, value);
  version += 1;
  for (const listener of listeners) listener();
}

/** Every slot the picker currently pins. */
export function activeOverrides(): ReadonlyMap<string, string> {
  return overrides;
}

/**
 * The arrangement this screen should render, resolved in Dart's own order:
 * the preview override, then the theme's classified pick, then the value that
 * ships.
 *
 * A pick outside `values` falls back rather than throwing — the vocabulary
 * lives in the app's `app.yaml` and this build may simply be older than it.
 * That degradation is the whole reason an unknown arrangement is a non-event
 * instead of a broken screen.
 */
export function useFormat<T extends string>(
  slot: string,
  values: readonly T[],
  fallback: T,
): T {
  useSyncExternalStore(subscribe, getVersion, getVersion);
  const config = useThemeConfig();
  const resolve = useCallback(
    (raw: string | undefined): T =>
      raw !== undefined && (values as readonly string[]).includes(raw) ? (raw as T) : fallback,
    [values, fallback],
  );
  const pinned = overrides.get(slot);
  if (pinned !== undefined) return resolve(pinned);
  return resolve(config?.formats[slot]);
}
