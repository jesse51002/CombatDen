// Ports ../../ThemeFlutter/lib/customization_service.dart (the `ThemeService`
// ChangeNotifier). The reactive primitive changes language — Flutter listens
// with a `ListenableBuilder`, React with `useSyncExternalStore` — but the
// contract is identical: one singleton holding the active theme, notifying on
// every change, and NEVER throwing.

import type { ThemeApiClient, ThemeStylesPageQuery } from '../api/client';
import type { ThemeConfig } from '../models/themeConfig';
import { parseThemeConfig } from '../models/themeConfig';
import type { ThemeStylesPage } from '../models/themeStylesPage';
import { computeAssetTargets, warmThemeAssets } from '../theme/assetWarmer';

import {
  readLastGood,
  readSelectedDesignId,
  writeLastGood,
  writeSelectedDesignId,
} from './persistence';

/**
 * The immutable view of the store React renders from.
 *
 * MUST be handed out as a CACHED reference: `useSyncExternalStore` throws
 * "The result of getSnapshot should be cached" and then loops forever if
 * `getSnapshot()` returns a fresh object literal per call. One frozen snapshot
 * is built inside `notify()` and the same reference is returned until the next
 * change. See `../__tests__/themeStore.test.ts`.
 */
export interface ThemeSnapshot {
  /** The loaded theme, or `null` when nothing loaded (network + disk both empty). */
  readonly config: ThemeConfig | null;
  /** The design currently loaded, for marking the active style in a picker. */
  readonly activeDesignId: string | null;
  /** Whether a theme is loaded at all. */
  readonly isLoaded: boolean;
  /** Whether `initialize()` has settled — the bootstrap gate, NOT "succeeded". */
  readonly isReady: boolean;
}

/** Slot ids the app expects; used ONLY for the loud missing-slot warning. */
export interface ThemeStoreOptions {
  expectedColors?: readonly string[];
  expectedImages?: readonly string[];
  expectedFonts?: readonly string[];
  expectedText?: readonly string[];
  expectedIcons?: readonly string[];
  /**
   * Accepted and documented as a NO-OP on the web — see `initializeTheme` in
   * ../runtime.ts for why it stays on the signature.
   */
  livePreview?: boolean;
}

const NO_KEYS: readonly string[] = Object.freeze([]);

/**
 * The pre-load snapshot. A frozen module constant so `getSnapshot()` is a cached
 * reference from the very first call, before anything has notified — and so the
 * locator can hand out the SAME object when no store exists at all.
 */
export const EMPTY_THEME_SNAPSHOT: ThemeSnapshot = Object.freeze({
  config: null,
  activeDesignId: null,
  isLoaded: false,
  isReady: false,
});

/**
 * Singleton holding the active theme.
 *
 * Fully app-agnostic: it parses whatever the backend returns into typed-value
 * maps and validates against the `expected*` slot ids the app declares. Missing
 * expected slots are warned about LOUDLY — never thrown — so the app always
 * runs on fallbacks.
 *
 * Loaded once at startup along the fallback ladder: localStorage last-good ►
 * fresh network ► per-call defaults. `initialize()` never throws.
 */
export class ThemeStore {
  private readonly client: ThemeApiClient;
  private readonly expectedColors: readonly string[];
  private readonly expectedImages: readonly string[];
  private readonly expectedFonts: readonly string[];
  private readonly expectedText: readonly string[];
  private readonly expectedIcons: readonly string[];

  private readonly listeners = new Set<() => void>();

  private config: ThemeConfig | null = null;
  private designId: string | null = null;
  private initialized = false;
  private snapshot: ThemeSnapshot = EMPTY_THEME_SNAPSHOT;

  /**
   * Kept so a consumer can read what it asked for. The web has ONE HTTP cache
   * and no JS API to opt an image out of it, so nothing here branches on it.
   */
  readonly livePreview: boolean;

  constructor(client: ThemeApiClient, options: ThemeStoreOptions = {}) {
    this.client = client;
    this.expectedColors = options.expectedColors ?? NO_KEYS;
    this.expectedImages = options.expectedImages ?? NO_KEYS;
    this.expectedFonts = options.expectedFonts ?? NO_KEYS;
    this.expectedText = options.expectedText ?? NO_KEYS;
    this.expectedIcons = options.expectedIcons ?? NO_KEYS;
    this.livePreview = options.livePreview ?? false;
  }

  /** The loaded theme, or `null`. */
  get current(): ThemeConfig | null {
    return this.config;
  }

  /** The design currently loaded. */
  get activeDesignId(): string | null {
    return this.designId;
  }

  /** Registers a listener; returns the unsubscribe. Ports `addListener`. */
  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  /** The cached snapshot. Never builds a new object — see `ThemeSnapshot`. */
  getSnapshot = (): ThemeSnapshot => this.snapshot;

  /**
   * The fallback ladder, in order:
   *
   *   1. Read the localStorage last-good copy and adopt it, so the very first
   *      render is already branded rather than bare-fallback.
   *   2. Resolve the active design as `localStorage selection ?? the designId
   *      this store was constructed with` — a pick made on a previous visit
   *      outranks the build-time seed.
   *   3. Fetch that design over the network under a hard 5s cap. On success,
   *      adopt it and persist it as the new last-good.
   *   4. On ANY failure — offline, 404, timeout, malformed payload — log and
   *      keep whatever step 1 gave us (or nothing, and every resolver returns
   *      its caller's fallback).
   *
   * Never throws.
   */
  initialize = async (): Promise<void> => {
    const cached = readLastGood();
    if (cached !== null) this.tryAdopt(cached);

    this.designId = readSelectedDesignId() ?? this.client.designId;

    try {
      const json = await this.client.fetchOutput(this.designId);
      const raw = JSON.stringify(json);
      if (this.tryAdopt(raw)) writeLastGood(raw);
    } catch (error) {
      console.warn('[theme] refresh failed, keeping last-good/defaults:', error);
    }

    this.initialized = true;
    this.warnMissingSlots();
    this.notify();
    this.warmAssets();
  };

  /**
   * Switches the live style: fetches `designId`, adopts it, persists it as
   * last-good AND as the sticky selection, and notifies so the whole tree
   * re-themes. Returns whether the switch took effect. Never throws — on any
   * failure the current theme stays completely intact.
   */
  selectDesign = async (designId: string): Promise<boolean> => {
    try {
      const json = await this.client.fetchOutput(designId);
      const raw = JSON.stringify(json);
      if (!this.tryAdopt(raw)) return false;
      this.designId = designId;
      writeLastGood(raw);
      writeSelectedDesignId(designId);
      this.warnMissingSlots();
      this.notify();
      this.warmAssets();
      return true;
    } catch (error) {
      console.warn('[theme] selectDesign failed, keeping current theme:', error);
      return false;
    }
  };

  /** One page of the app's selectable styles. */
  fetchStylesPage = (query: ThemeStylesPageQuery = {}): Promise<ThemeStylesPage> =>
    this.client.fetchStylesPage(query);

  /** Absolutises a raw slot URL. */
  resolveImageUrl = (raw: string): string => this.client.resolveImageUrl(raw);

  private tryAdopt = (rawJson: string): boolean => {
    try {
      this.config = parseThemeConfig(JSON.parse(rawJson));
      return true;
    } catch (error) {
      console.warn('[theme] parse failed, ignoring payload:', error);
      return false;
    }
  };

  private notify = (): void => {
    this.snapshot = Object.freeze({
      config: this.config,
      activeDesignId: this.designId,
      isLoaded: this.config !== null,
      isReady: this.initialized,
    });
    // Copy first: a listener is free to unsubscribe inside its own callback.
    for (const listener of [...this.listeners]) listener();
  };

  private warmAssets = (): void => {
    warmThemeAssets(computeAssetTargets(this.config, this.client.resolveImageUrl));
  };

  /**
   * Ports `_warnMissingSlots`. A slot the app declared but the backend did not
   * ship is a CONTENT bug (the run needs an `expand`), not a client bug — so it
   * is shouted about in the console and then ignored, and the call site's
   * fallback renders.
   */
  private warnMissingSlots = (): void => {
    const config = this.config;
    const missingColors = this.expectedColors.filter(
      (key) => (config?.colors[key]?.color ?? null) === null,
    );
    const missingImages = missing(this.expectedImages, config?.images);
    const missingFonts = missing(this.expectedFonts, config?.fonts);
    const missingTexts = missing(this.expectedText, config?.texts);
    const missingIcons = missing(this.expectedIcons, config?.icons);
    if (
      missingColors.length === 0 &&
      missingImages.length === 0 &&
      missingFonts.length === 0 &&
      missingTexts.length === 0 &&
      missingIcons.length === 0
    ) {
      return;
    }
    console.warn(
      [
        '',
        '========================================================',
        '[THEME] MISSING EXPECTED SLOTS — using fallbacks',
        `  loaded: ${config !== null ? config.app : '<nothing>'}`,
        `  colors missing: ${list(missingColors)}`,
        `  images missing: ${list(missingImages)}`,
        `  fonts missing : ${list(missingFonts)}`,
        `  texts missing : ${list(missingTexts)}`,
        `  icons missing : ${list(missingIcons)}`,
        '========================================================',
        '',
      ].join('\n'),
    );
  };
}

function missing(
  expected: readonly string[],
  slots: Readonly<Record<string, string>> | undefined,
): string[] {
  return expected.filter((key) => (slots?.[key] ?? '') === '');
}

function list(keys: readonly string[]): string {
  return keys.length === 0 ? '-' : keys.join(', ');
}
