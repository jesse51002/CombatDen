// Ports ../../../../../LandingPage/hifi/copy.jsx lines 17-24 — `COPY.nav`.
//
// ABSOLUTISED, the same way the Flutter standalone browser did it (see
// ../../../../../CRM/lib/features/theme_browser/presentation/widgets/
// theme_browser_top_bar.dart lines 30-41): copy.jsx ships page-relative hrefs
// because it renders ON www.combatden.net, and this app is served from a
// DIFFERENT host (themes.combatden.net), where `index.html` / `pricing.html` /
// `#book` would resolve against the wrong origin.
//
//   index.html    → https://www.combatden.net
//   pricing.html  → https://www.combatden.net/pricing.html
//   #book         → https://www.combatden.net/#book
//
// The `Themes` link is already absolute in copy.jsx and points at this very
// app; it is kept so the nav reads identically to the marketing site's.

export interface NavLink {
  readonly label: string;
  readonly href: string;
}

/** The landing site's root — the wordmark's target, and the `Home` link's. */
export const LANDING_URL = 'https://www.combatden.net';
export const PRICING_URL = 'https://www.combatden.net/pricing.html';
export const BOOK_URL = 'https://www.combatden.net/#book';

export const NAV_LINKS: readonly NavLink[] = Object.freeze([
  { label: 'Home', href: LANDING_URL },
  { label: 'Themes', href: 'https://themes.combatden.net' },
  { label: 'Pricing', href: PRICING_URL },
]);

/** `COPY.nav.cta`. */
export const NAV_CTA = 'Book a demo';

/** `COPY.cta.demo` — `GWButton`'s default label. */
export const CTA_DEMO = 'Book a 15-minute demo';
