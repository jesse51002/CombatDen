// Ports ../../../../../CRM/lib/showcase/showcase_content.dart, plus the
// `_fillSlots` rule from ../../../../../CRM/lib/features/members/presentation/
// widgets/member_app/theme_tab/theme_preview_pane.dart:23-27.
//
// The gym content the phone previews: reward cards and class cards, in exactly
// the shape the gym file carries (VideoService's `gyms/*.yaml`). The showcase
// maps them onto its own schedule / store models; class TIME SLOTS are
// synthesised by ./home/homeScheduleGenerator.ts, because a gym file has no
// schedule.
//
// In THIS app the "real" list is always absent — the public browser has no gym,
// no auth and no member data — so `fillSlots` always takes the defaults branch.
// It is ported whole anyway: it is the contract the admin preview shares, and
// the one-item repeat is the rule that keeps a gym with a single class from
// rendering one lonely card in a four-card layout.

/** One points-store reward to preview (maps to a store-grid card). */
export interface ShowcaseReward {
  readonly title: string;
  /** Network image — the gym serves URLs. */
  readonly imageUrl: string;
  /** Paid on top of points: "Free", "30% off". */
  readonly priceLabel: string;
  readonly pointsCost: number;
}

/**
 * One class card to preview (maps to a schedule row; its time slot is
 * synthesised by the schedule generator).
 */
export interface ShowcaseClassInfo {
  readonly name: string;
  /** Network image — the gym serves URLs. */
  readonly imageUrl: string;
  /** Shown as the class mentor. */
  readonly instructorName: string;
}

/**
 * Ports `_fillSlots`. Returns `defaults` when `real` is null/empty; when `real`
 * holds EXACTLY ONE item, repeats it across all `defaults.length` slots so the
 * single item fills every schedule / store card instead of appearing once.
 */
export function fillSlots<T>(real: readonly T[] | null | undefined, defaults: readonly T[]): readonly T[] {
  if (real === null || real === undefined || real.length === 0) return defaults;
  const only = real[0];
  if (real.length === 1 && only !== undefined) {
    return Array.from({ length: defaults.length }, () => only);
  }
  return real;
}
