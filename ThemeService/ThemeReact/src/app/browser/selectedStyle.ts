// Ports the THEME HALF of
// ../../../../../CRM/lib/core/state/selected_gym.dart — `selectStyle`
// (lines 260-269) and `reconcileFromCatalog` (lines 302-314), plus the two
// fields they own (`_designId`, `_themeCategory`).
//
// NOTHING ELSE OF THAT FILE PORTS. `SelectedGym` also carries the admin's real
// gym — its uuid, name, logo, Stripe account, VideoService id, and a Supabase
// -backed `fetchShowcase` detail load. This app is the PUBLIC browser: there is
// no gym, no auth, and no backend but ThemeService's read API, so the gym half
// has nothing to hold. The class is renamed to match what survives.
//
// The store is a module singleton with a CACHED snapshot, exactly like
// theme-react's own stores — `useSyncExternalStore` throws "The result of
// getSnapshot should be cached" and loops forever on a fresh object literal per
// call (see ../../../CLAUDE.md).

import { useSyncExternalStore } from 'react';
import { activeDesignId, selectDesign } from 'theme-react';
import type { ThemeStyle } from 'theme-react';

/** What the browser knows about the style being previewed. */
export interface SelectedStyleState {
  /** The previewed design's id, or `null` before anything is picked. */
  readonly designId: string | null;
  /**
   * The previewed design's showcase category (`Fighting`, `Yoga`, …). Null
   * until a pick or a catalog reconcile supplies it — a seeded or deep-linked
   * design arrives as an id with no category attached.
   */
  readonly category: string | null;
}

const EMPTY: SelectedStyleState = Object.freeze({ designId: null, category: null });

class SelectedStyleStore {
  private readonly listeners = new Set<() => void>();

  private state: SelectedStyleState = EMPTY;

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  /** The cached state. Same reference until something actually changes. */
  getSnapshot = (): SelectedStyleState => this.state;

  /**
   * Select `style` from the picker: record the previewed design id + its
   * category and re-brand the live preview. No-op if it is already the
   * previewed design.
   */
  selectStyle = (style: ThemeStyle): void => {
    if (this.state.designId === style.id && this.state.category === style.category) return;
    this.state = Object.freeze({ designId: style.id, category: style.category });
    // Drive branding; idempotent — skip when the engine is already on it.
    if (style.id !== '' && activeDesignId() !== style.id) {
      void selectDesign(style.id);
    }
    this.notify();
  };

  /**
   * Resolve `category` from a loaded style catalog for the currently previewed
   * `designId` when the category isn't known yet — a seeded or deep-linked
   * theme carries only its id (via the URL), not its category, until its
   * catalog row streams in. **Only fires when no category is locked in yet**,
   * so an explicit pick is never overridden. Matches on the intended
   * `designId`, falling back to the engine's active design (which the seed
   * applied).
   */
  reconcileFromCatalog = (items: Iterable<ThemeStyle>): void => {
    if (this.state.category !== null) return; // category known — don't override a pick
    const target = this.state.designId ?? activeDesignId();
    if (target === null || target === '') return;
    for (const style of items) {
      if (style.id === target) {
        this.state = Object.freeze({ designId: target, category: style.category });
        this.notify();
        return;
      }
    }
  };

  private notify = (): void => {
    for (const listener of [...this.listeners]) listener();
  };
}

/** The one process-wide selected style, watched by the browser surfaces. */
export const selectedStyle = new SelectedStyleStore();

/** Subscribes a component to the selection. */
export function useSelectedStyle(): SelectedStyleState {
  return useSyncExternalStore(
    selectedStyle.subscribe,
    selectedStyle.getSnapshot,
    selectedStyle.getSnapshot,
  );
}
