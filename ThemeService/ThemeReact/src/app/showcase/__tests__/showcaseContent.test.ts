// `fillSlots` (../showcaseContent.ts) and the schedule generator
// (../home/homeScheduleGenerator.ts) — the two pieces of the home port whose
// behaviour is arithmetic rather than layout.
//
// `fillSlots` ports theme_preview_pane.dart:23-27. Its middle case is the one
// worth pinning: a gym with EXACTLY ONE class must fill all four schedule
// cards, not render one lonely row in a four-row layout.

import { describe, expect, it } from 'vitest';

import { dayAt, formatDayLabel, formatFullDayLabel } from '../home/homeScheduleGenerator';
import type { ShowcaseClassInfo } from '../showcaseContent';
import { fillSlots } from '../showcaseContent';

const DEFAULTS = ['a', 'b', 'c', 'd'];

describe('fillSlots', () => {
  it('falls back when the real list is absent or empty', () => {
    expect(fillSlots(null, DEFAULTS)).toEqual(DEFAULTS);
    expect(fillSlots(undefined, DEFAULTS)).toEqual(DEFAULTS);
    expect(fillSlots([], DEFAULTS)).toEqual(DEFAULTS);
  });

  it('repeats a single real item across every default slot', () => {
    expect(fillSlots(['only'], DEFAULTS)).toEqual(['only', 'only', 'only', 'only']);
  });

  it('passes two or more real items through untouched', () => {
    expect(fillSlots(['x', 'y'], DEFAULTS)).toEqual(['x', 'y']);
  });
});

describe('day labels', () => {
  it('names the first two days rather than dating them', () => {
    expect(formatDayLabel(0)).toBe('Today');
    expect(formatDayLabel(1)).toBe('Tomorrow');
    expect(formatFullDayLabel(0)).toBe('Today');
    expect(formatFullDayLabel(1)).toBe('Tomorrow');
  });

  it('dates the rest, abbreviated in the strip and full in the heading', () => {
    // Dart's `DateTime.weekday` is 1..7 from Monday; JS puts Sunday at 0, so
    // the mapping is the one thing that can silently go a day out.
    expect(formatDayLabel(3)).toMatch(/^(Mon|Tue|Wed|Thu|Fri|Sat|Sun) \d{2}$/);
    expect(formatFullDayLabel(3)).toMatch(
      /^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday) \d{2}$/,
    );
  });
});

describe('dayAt', () => {
  it('renders the four bundled samples when no gym content is injected', () => {
    const day = dayAt(0);
    expect(day.classes).toHaveLength(4);
    expect(day.classes.map((c) => c.name)).toEqual([
      'Fundamentals',
      'Striking & Pads',
      'Open Mat Sparring',
      'Conditioning',
    ]);
  });

  it('borrows a time slot per index for injected gym classes', () => {
    const injected: ShowcaseClassInfo[] = [
      { name: 'Sunrise Flow', imageUrl: 'https://example.test/a.jpg', instructorName: 'Coach A' },
      { name: 'Power Vinyasa', imageUrl: 'https://example.test/b.jpg', instructorName: 'Coach B' },
    ];
    const day = dayAt(0, injected);
    expect(day.classes.map((c) => c.name)).toEqual(['Sunrise Flow', 'Power Vinyasa']);
    expect(day.classes.map((c) => c.mentor)).toEqual(['Coach A', 'Coach B']);
    // Gym files carry no schedule, so the samples' slots are reused by index.
    expect(day.classes[0]?.timeRange).toBe('9:00am - 9:55am');
    expect(day.classes[1]?.timeRange).toBe('11:00am - 11:55am');
    expect(day.classes[0]?.imageUrl).toBe('https://example.test/a.jpg');
  });

  it('is deterministic: the same day always shows the same demo numbers', () => {
    const first = dayAt(2);
    const second = dayAt(2);
    expect(first.classes.map((c) => c.attending)).toEqual(second.classes.map((c) => c.attending));
    expect(first.classes.map((c) => c.isBooked)).toEqual(second.classes.map((c) => c.isBooked));
  });

  it('keeps the attending counts inside the Dart range', () => {
    for (let offset = 0; offset < 14; offset += 1) {
      for (const item of dayAt(offset).classes) {
        expect(item.attending).toBeGreaterThanOrEqual(10);
        expect(item.attending).toBeLessThanOrEqual(40);
      }
    }
  });

  it('books the slots the ported pattern books', () => {
    // `(day * 4 + i) % 7 == 0 || (day * 3 + i * 2) % 11 == 0`, ported verbatim.
    expect(dayAt(0).classes.map((c) => c.isBooked)).toEqual([true, false, false, false]);
    expect(dayAt(7).classes.map((c) => c.isBooked)).toEqual([true, false, false, false]);
  });
});
