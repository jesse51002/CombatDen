// Ports ../../../../../CRM/lib/shared/widgets/fill_grid.dart.
//
// A grid whose cells stretch to fill the row width, so it always aligns flush
// with its container with no ragged gap at the end of a row. Every column is
// the same width and the last row's empty cells are reserved, so items stay
// aligned to the columns above them.
//
// Pass `minItemWidth` for a responsive column count that scales with the
// container (as many columns as fit at that minimum), or `columns` for a fixed
// count. With `minItemWidth`, `minColumns` sets a floor on the responsive count
// so a narrow viewport never collapses below it.
//
// By default a collection smaller than the column count `stretchShortRows`: the
// column count is capped at the item count so a short row fills the width with
// no ragged trailing gap. Pass `stretchShortRows={false}` to keep the column
// count fixed instead — a short collection then leaves reserved empty cells, so
// each item keeps its normal column width (e.g. a single search result sits as
// one normal card in the top-left rather than ballooning to fill the row).
//
// WHY THIS IS NOT `repeat(auto-fill, minmax(280px, 1fr))`: `auto-fill` has no
// way to express the `minColumns` FLOOR. Below 2×280+16 it drops to one column,
// which is exactly what the Dart widget's `math.max(minColumns, fit)` exists to
// prevent. The column count is therefore computed from a measured width (see
// ./useElementSize.ts) and written into `grid-template-columns`, which is the
// same arithmetic Dart runs inside `LayoutBuilder`.

import type { ReactNode } from 'react';

import { ADM } from '../tokens/adminTokens';

import styles from './FillGrid.module.css';
import { useElementSize } from './useElementSize';

export interface FillGridProps {
  children: readonly ReactNode[];
  /** Fixed column count, used when `minItemWidth` is absent. */
  columns?: number;
  /** Responsive: as many columns as fit at this minimum cell width. */
  minItemWidth?: number;
  /** Floor under the responsive count. */
  minColumns?: number;
  spacing?: number;
  stretchShortRows?: boolean;
}

/**
 * The column count for a container of `width`. Exported for the unit test —
 * this arithmetic IS the widget, and it is the one part CSS could not express.
 */
export function fillGridColumns({
  width,
  itemCount,
  columns = 3,
  minItemWidth,
  minColumns = 1,
  spacing = ADM.spacingLarge,
  stretchShortRows = true,
}: {
  width: number;
  itemCount: number;
  columns?: number;
  minItemWidth?: number;
  minColumns?: number;
  spacing?: number;
  stretchShortRows?: boolean;
}): number {
  if (minItemWidth === undefined) {
    const cols = stretchShortRows ? Math.min(columns, itemCount) : columns;
    return Math.max(1, cols);
  }
  const fit = Math.floor((width + spacing) / (minItemWidth + spacing));
  // Hold a floor of `minColumns` so a narrow viewport keeps a sensible grid
  // instead of a single stacked column.
  const desired = Math.max(minColumns, fit);
  // By default never reserve more columns than there are items, so a short row
  // stretches to fill the width instead of leaving a ragged gap. With
  // `stretchShortRows` off the count stays fixed and the short row's empty
  // cells are reserved, keeping each card at column width.
  const cols = stretchShortRows ? Math.min(desired, itemCount) : desired;
  return Math.max(1, cols);
}

export function FillGrid({
  children,
  columns = 3,
  minItemWidth,
  minColumns = 1,
  spacing = ADM.spacingLarge,
  stretchShortRows = true,
}: FillGridProps) {
  const [measureRef, { width }] = useElementSize<HTMLDivElement>();
  const cols = fillGridColumns({
    width,
    itemCount: children.length,
    columns,
    ...(minItemWidth === undefined ? {} : { minItemWidth }),
    minColumns,
    spacing,
    stretchShortRows,
  });
  return (
    <div
      ref={measureRef}
      className={styles.grid}
      style={{ gap: `${spacing}px`, gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))` }}
    >
      {children}
    </div>
  );
}
