// Ports ../../../../../../CRM/lib/showcase/home/home_class.dart — a clone of
// MobileApp's `MockClass` / `MockDay` home-schedule models.
//
// The real member screen fetches its classes from VideoService; the showcase
// carries bundled sample data instead, so it renders with no backend at all.
// `imageAsset` is a bundled filename (resolved through ../showcaseAssets.ts);
// `imageUrl` is an injected gym photo (a network URL) and wins over it.

import type { ShowcaseAssetFile } from '../showcaseAssets';

export interface ShowcaseClass {
  readonly name: string;
  readonly timeRange: string;
  readonly durationMinutes: number;
  /** Instructor display name. */
  readonly mentor: string;
  /** Bundled class-photo filename. Ignored when `imageUrl` is set. */
  readonly imageAsset?: ShowcaseAssetFile | undefined;
  /** Injected gym class photo (a network URL); wins over `imageAsset`. */
  readonly imageUrl?: string | undefined;
  readonly attending?: number | undefined;
  readonly isBooked: boolean;
}

export interface ShowcaseDay {
  readonly label: string;
  readonly classes: readonly ShowcaseClass[];
}

/**
 * The four daily classes, mirroring VideoService's four-class feed. The
 * schedule generator loops these into the fixed time slots, one per slot.
 */
export const SHOWCASE_CLASSES: readonly ShowcaseClass[] = Object.freeze([
  {
    name: 'Fundamentals',
    timeRange: '9:00am - 9:55am',
    durationMinutes: 55,
    mentor: 'Coach Marcus Reyes',
    imageAsset: 'class_photo_1.png',
    isBooked: false,
  },
  {
    name: 'Striking & Pads',
    timeRange: '11:00am - 11:55am',
    durationMinutes: 55,
    mentor: 'Coach Dana Whitfield',
    imageAsset: 'class_photo_2.png',
    isBooked: false,
  },
  {
    name: 'Open Mat Sparring',
    timeRange: '6:00pm - 6:55pm',
    durationMinutes: 55,
    mentor: 'Coach Leo Tanaka',
    imageAsset: 'class_photo_3.png',
    isBooked: false,
  },
  {
    name: 'Conditioning',
    timeRange: '7:00pm - 7:55pm',
    durationMinutes: 55,
    mentor: 'Coach Priya Nair',
    imageAsset: 'class_photo_4.png',
    isBooked: false,
  },
]);
