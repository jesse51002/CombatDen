// `fillGridColumns` is the arithmetic CSS could not express — the `minColumns`
// FLOOR that `repeat(auto-fill, minmax(…))` has no way to state. It ports
// CRM/lib/shared/widgets/fill_grid.dart's `LayoutBuilder` body, so it is pinned
// here against the same cases the Dart widget is used with.

import { describe, expect, it } from 'vitest';

import { fillGridColumns } from '../widgets/FillGrid';

// The library grid's own settings (library_view.dart:22-23 + its FillGrid call).
const LIBRARY = { minItemWidth: 280, minColumns: 2, spacing: 16, stretchShortRows: false } as const;

describe('fillGridColumns', () => {
  it('fits as many columns as the width allows', () => {
    // (1200 + 16) / (280 + 16) = 4.10 → 4
    expect(fillGridColumns({ width: 1200, itemCount: 40, ...LIBRARY })).toBe(4);
    // (900 + 16) / 296 = 3.09 → 3
    expect(fillGridColumns({ width: 900, itemCount: 40, ...LIBRARY })).toBe(3);
  });

  it('never drops below minColumns, however narrow', () => {
    expect(fillGridColumns({ width: 320, itemCount: 40, ...LIBRARY })).toBe(2);
    // The pre-measurement frame, and the reason a `0` default is safe.
    expect(fillGridColumns({ width: 0, itemCount: 40, ...LIBRARY })).toBe(2);
  });

  it('keeps a short result at column width when stretchShortRows is off', () => {
    // One search hit stays one normal card in the top-left, not a full-width one.
    expect(fillGridColumns({ width: 1200, itemCount: 1, ...LIBRARY })).toBe(4);
  });

  it('caps the count at the item count when stretchShortRows is on', () => {
    expect(
      fillGridColumns({ ...LIBRARY, stretchShortRows: true, width: 1200, itemCount: 1 }),
    ).toBe(1);
  });

  it('returns at least one column for an empty stretchable collection', () => {
    expect(
      fillGridColumns({ ...LIBRARY, stretchShortRows: true, width: 1200, itemCount: 0 }),
    ).toBe(1);
  });

  it('uses the fixed count when no minItemWidth is given', () => {
    expect(fillGridColumns({ width: 1200, itemCount: 40, columns: 3 })).toBe(3);
  });
});
