// Ports ../../../../../../CRM/lib/showcase/home/home_schedule_generator.dart —
// a clone of MobileApp's `schedule_generator.dart`. Builds one day's schedule by
// looping the sample classes into fixed time slots, with deterministic
// demo-only attending / booked flags.
//
// DEVIATION, and the only one: `_seededAttending` uses `Random(seed).nextInt(31)`
// — dart:math's own 64-bit LCG. Reproducing that bit stream in JS would need
// BigInt and would buy nothing: what the Dart code needs from it is that the
// number be DETERMINISTIC per (dayOffset, classIndex) and land in [10, 40], so
// the same phone always shows the same counts and a screenshot is stable. The
// seed formula (`dayOffset * 7 + classIndex * 13`) and the range are ported
// exactly; the mixing function is a small integer hash instead.

import type { ShowcaseClassInfo } from '../showcaseContent';

import type { ShowcaseClass, ShowcaseDay } from './homeClass';
import { SHOWCASE_CLASSES } from './homeClass';

/** `_weekdayAbbr` — indexed by Dart's `DateTime.weekday` (1 = Monday). */
const WEEKDAY_ABBR: readonly string[] = Object.freeze([
  '',
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
]);

/** `_weekdayFull`. */
const WEEKDAY_FULL: readonly string[] = Object.freeze([
  '',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
]);

/** `_todayMidnight`. */
function todayMidnight(): Date {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), now.getDate());
}

/** Dart's `DateTime.weekday`: 1 = Monday … 7 = Sunday. JS puts Sunday at 0. */
function dartWeekday(date: Date): number {
  const day = date.getDay();
  return day === 0 ? 7 : day;
}

/** `_twoDigit`. */
function twoDigit(n: number): string {
  return String(n).padStart(2, '0');
}

function dayOffsetDate(dayOffset: number): Date {
  const date = todayMidnight();
  date.setDate(date.getDate() + dayOffset);
  return date;
}

/** `formatDayLabel` — the date-strip pill. */
export function formatDayLabel(dayOffset: number): string {
  if (dayOffset === 0) return 'Today';
  if (dayOffset === 1) return 'Tomorrow';
  const date = dayOffsetDate(dayOffset);
  return `${WEEKDAY_ABBR[dartWeekday(date)] ?? ''} ${twoDigit(date.getDate())}`;
}

/** `formatFullDayLabel` — the day heading over a class group. */
export function formatFullDayLabel(dayOffset: number): string {
  if (dayOffset === 0) return 'Today';
  if (dayOffset === 1) return 'Tomorrow';
  const date = dayOffsetDate(dayOffset);
  return `${WEEKDAY_FULL[dartWeekday(date)] ?? ''} ${twoDigit(date.getDate())}`;
}

/**
 * `_seededAttending` — a stable 10..40 for a (day, class) pair. See the header
 * for why the mixer differs from dart:math's.
 */
function seededAttending(dayOffset: number, classIndex: number): number {
  const seed = dayOffset * 7 + classIndex * 13;
  // A 32-bit integer avalanche (the xorshift-multiply mixer), so adjacent seeds
  // do not produce adjacent counts.
  let h = seed >>> 0;
  h = Math.imul(h ^ (h >>> 16), 0x45d9f3b) >>> 0;
  h = Math.imul(h ^ (h >>> 16), 0x45d9f3b) >>> 0;
  h = (h ^ (h >>> 16)) >>> 0;
  return 10 + (h % 31);
}

/**
 * `_isClassBooked` — ported exactly. A deterministic pattern giving ~1-2 booked
 * classes per ~3 days, varied across both axes so the visual mix matches the
 * design without any real state.
 */
function isClassBooked(dayOffset: number, classIndex: number): boolean {
  return (
    (dayOffset * 4 + classIndex) % 7 === 0 || (dayOffset * 3 + classIndex * 2) % 11 === 0
  );
}

/**
 * `_baseClasses` — the host's injected gym `classes` when provided (time slots
 * borrowed from the samples BY INDEX, since a gym file carries no schedule),
 * else the bundled samples.
 */
function baseClasses(classes: readonly ShowcaseClassInfo[] | null | undefined): readonly ShowcaseClass[] {
  if (classes === null || classes === undefined || classes.length === 0) return SHOWCASE_CLASSES;
  return classes.map((info, i) => {
    const sample = SHOWCASE_CLASSES[i % SHOWCASE_CLASSES.length];
    return {
      name: info.name,
      // A plausible time slot borrowed from the samples.
      timeRange: sample?.timeRange ?? '',
      durationMinutes: sample?.durationMinutes ?? 0,
      mentor: info.instructorName,
      imageUrl: info.imageUrl,
      // DEVIATION, and a deliberate one: Dart borrows only the TIME from the
      // sample, so an injected class whose `image_url` came back null resolves
      // `AssetImage('assets/showcase/')`, fails, and paints a flat `card`
      // rectangle. Borrowing the sample's photo by the same index rule gives
      // four different plausible photos instead of four grey boxes, and the
      // gym's own URL still wins whenever it is present.
      imageAsset: sample?.imageAsset,
      isBooked: false,
    };
  });
}

/**
 * `dayAt` — one day's schedule, class i at slot i. Every day shows the same
 * classes at the same times; the per-day variation is only the demo attending /
 * booked flags. Pass `classes` to preview a real gym's classes.
 */
export function dayAt(
  dayOffset: number,
  classes?: readonly ShowcaseClassInfo[] | null,
): ShowcaseDay {
  const base = baseClasses(classes);
  return {
    label: formatFullDayLabel(dayOffset),
    classes: base.map((item, i) => ({
      name: item.name,
      timeRange: item.timeRange,
      durationMinutes: item.durationMinutes,
      mentor: item.mentor,
      imageAsset: item.imageAsset,
      imageUrl: item.imageUrl,
      attending: seededAttending(dayOffset, i),
      isBooked: isClassBooked(dayOffset, i),
    })),
  };
}
