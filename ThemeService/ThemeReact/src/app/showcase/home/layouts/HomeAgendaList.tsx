// Ports MobileApp/lib/features/home/presentation/layouts/home_agenda_list.dart.
//
// `HomeFormat.agendaList` — THE ARRANGEMENT THAT SHIPS TODAY.
//
// A pinned date rail over vertically stacked day groups, each class a
// text-left / thumb-right row. Reproduces the previous home body element for
// element, so a tenant with no `home_format` slot sees no change;
// ../__tests__/homeFormats.test.tsx pins that against a captured baseline.

import { HomeScheduleScroll } from './HomeScheduleScroll';
import type { HomeLayoutProps } from './homeLayout';

export function HomeAgendaList({ topbar, classes }: HomeLayoutProps) {
  return <HomeScheduleScroll topbar={topbar} classes={classes} />;
}
