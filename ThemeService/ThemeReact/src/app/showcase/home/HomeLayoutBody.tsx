// Ports MobileApp/lib/features/home/presentation/layouts/home_layout_body.dart.
//
// The schedule, arranged by the tenant's `home_format` slot.
//
// Takes its data as props and fetches nothing, so every arrangement can be
// exercised without a content ladder — see ./__tests__/homeFormats.test.tsx,
// which is the gate that proves each value renders the same element set.
//
// `format` is a PROP, not a hook read, and that is deliberate on both ends:
// ./HomeShowcase.tsx resolves it once through `useFormat` (the override → the
// theme's classified pick → the value that ships), and the invariant test
// forces each value directly the way Dart's `formatOverride` does. Neither path
// can reach data the others cannot.

import { HomeAgendaList } from './layouts/HomeAgendaList';
import { HomeBoardGrid } from './layouts/HomeBoardGrid';
import { HomeDayPager } from './layouts/HomeDayPager';
import { HomeNextUpHero } from './layouts/HomeNextUpHero';
import { HomeTimeSpine } from './layouts/HomeTimeSpine';
import type { HomeLayoutProps } from './layouts/homeLayout';
import type { HomeFormat } from '../formats';

export interface HomeLayoutBodyProps extends HomeLayoutProps {
  format: HomeFormat;
}

export function HomeLayoutBody({ format, topbar, classes }: HomeLayoutBodyProps) {
  switch (format) {
    case 'agendaList':
      return <HomeAgendaList topbar={topbar} classes={classes} />;
    case 'dayPager':
      return <HomeDayPager topbar={topbar} classes={classes} />;
    case 'timeSpine':
      return <HomeTimeSpine topbar={topbar} classes={classes} />;
    case 'nextUpHero':
      return <HomeNextUpHero topbar={topbar} classes={classes} />;
    case 'boardGrid':
      return <HomeBoardGrid topbar={topbar} classes={classes} />;
  }
}
