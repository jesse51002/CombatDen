// Ports Flutter's `LayoutBuilder` — the "tell me how big I actually am"
// primitive that three ported surfaces build their layout on:
// ../../../../../CRM/lib/shared/widgets/fill_grid.dart (column count),
// .../member_app/theme_tab/live_theme_preview_tab.dart (the 700px split), and
// .../shared/widgets/phone_frame.dart (`FittedBox`'s contain scale).
//
// CSS cannot express any of the three: `auto-fill` has no `minColumns` floor, a
// media query measures the VIEWPORT rather than the widget's own box, and
// `aspect-ratio` + `max-height` does NOT re-derive the width when the height is
// the binding constraint (only a size DERIVED from the ratio does), so a
// contain-fit inside an arbitrary box has to be computed. The measurement is a
// ResizeObserver and the result is handed back as numbers, exactly as
// `LayoutBuilder` hands `constraints` down.

import { useCallback, useState } from 'react';

export interface ElementSize {
  readonly width: number;
  readonly height: number;
}

const ZERO: ElementSize = Object.freeze({ width: 0, height: 0 });

/**
 * Returns a ref callback to attach to the element, and its current content box.
 *
 * `initial` is what is reported for the single frame before the first
 * measurement lands. It defaults to zero — the narrowest sensible layout, never
 * a guess at a wide one — but a caller whose element is known to track the
 * viewport can seed it to skip a visible reflow; either way the real
 * measurement replaces it on the first commit.
 */
export function useElementSize<T extends Element>(
  initial: ElementSize = ZERO,
): [(node: T | null) => void, ElementSize] {
  const [size, setSize] = useState<ElementSize>(initial);

  // A ref callback, not an effect + a ref read: writing to (or reading) a ref
  // during render is forbidden by the React Compiler lint rules this package
  // runs under, and the ref callback fires at commit with the node in hand.
  const measureRef = useCallback((node: T | null) => {
    if (node === null) return;
    const apply = (width: number, height: number) => {
      // Same reference when nothing moved, so a resize that does not change the
      // box never costs a render.
      setSize((current) =>
        current.width === width && current.height === height ? current : { width, height },
      );
    };
    const box = node.getBoundingClientRect();
    apply(box.width, box.height);
    // jsdom (the test environment) has no ResizeObserver; one measurement is
    // the correct degradation there, not a crash.
    if (typeof ResizeObserver === 'undefined') return;
    const observer = new ResizeObserver((entries) => {
      const entry = entries[0];
      if (entry) apply(entry.contentRect.width, entry.contentRect.height);
    });
    observer.observe(node);
    return () => observer.disconnect();
  }, []);

  return [measureRef, size];
}
