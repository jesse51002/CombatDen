// The one payload every `class_format` arrangement receives.
//
// EVERY LAYOUT RECEIVES THE SAME DATA. A layout may change where these land and
// how prominent they are; it may not drop one, add one, or reach for anything
// not in here — which is what keeps a format an ARRANGEMENT and not a different
// screen. That sentence is `class_layout_data.dart`'s own, and it is the reason
// the five layouts share one props type instead of each declaring its own.
//
// `gymName` / `gymLogoSrc` are the HOST's gym identity rather than class data;
// they are here because every arrangement renders the topbar, and the topbar
// carries them. They are NOT customization slots — a theme pick must never
// rename the mock's gym.

import type { ClassDetail } from '../classDetail';

export interface ClassLayoutProps {
  detail: ClassDetail;
  gymName: string;
  /** The host gym's real logo URL. Absent in the public browser. */
  gymLogoSrc?: string | undefined;
}
