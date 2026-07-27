// Ports ../../../../../LandingPage/hifi/chrome.jsx — `GWNav`.
//
// THE INLINE `style={{}}` OBJECTS ARE VERBATIM AND MUST STAY THAT WAY — see
// ./GWButton.tsx's header for why.
//
// Sticky top nav. Becomes a translucent blurred bar on scroll. On mobile
// (useIsMobile) the link list collapses into a hamburger that toggles a
// dropdown panel with the links + CTA.
//
// FOUR DEVIATIONS, all forced by the host or the lint gate, all style-neutral
// (the fourth is documented at its call site):
//   1. `COPY` / `BRAND` are not globals here; they are imported.
//   2. The wordmark image is an imported asset (Vite hashes it into the
//      bundle) rather than the site-relative `assets/landing/logo_tiny.png`,
//      and the wordmark/CTA hrefs are the ABSOLUTE marketing URLs — this app
//      is served from a different host (see ./navCopy.ts).
//   3. The scroll listener's effect takes a `scrollRootKey` dep. chrome.jsx
//      runs it once with `[]` because the landing page's `[data-scroll-root]`
//      exists from the first paint; here the scrolling element is behind the
//      theme bootstrap gate and swaps between browser modes, so the host can
//      force a re-query. Default `undefined` reproduces the `[]` behaviour.

import { useEffect, useState } from 'react';

import { BRAND, GW } from '../tokens/gw';

import { GWButton } from './GWButton';
import logoTiny from './logo_tiny.png';
import { BOOK_URL, LANDING_URL, NAV_CTA, NAV_LINKS } from './navCopy';
import { MOBILE_Q, useIsMobile } from './useIsMobile';

export interface GWNavProps {
  /**
   * Changes whenever the host's `[data-scroll-root]` element is (re)mounted,
   * so the scroll listener re-attaches to the live one.
   */
  scrollRootKey?: string | number;
}

export function GWNav({ scrollRootKey }: GWNavProps) {
  const [scrolled, setScrolled] = useState(false);
  const isMobile = useIsMobile();
  const [open, setOpen] = useState(false);
  useEffect(() => {
    const el = document.querySelector('[data-scroll-root]') ?? window;
    const target = el === window ? window : el;
    const onScroll = () => {
      const y = el === window ? window.scrollY : (el as Element).scrollTop;
      setScrolled(y > 12);
    };
    target.addEventListener('scroll', onScroll, { passive: true });
    onScroll();
    return () => target.removeEventListener('scroll', onScroll);
  }, [scrollRootKey]);
  // leaving mobile (e.g. rotate to landscape / resize up) closes the menu.
  //
  // DEVIATION #4: chrome.jsx writes this as `useEffect(() => { if (!isMobile)
  // setOpen(false) }, [isMobile])`. A synchronous `setState` in an effect body
  // to reset derived state is exactly what `react-hooks`' `set-state-in-effect`
  // rule forbids here, and `--max-warnings 0` makes it fatal (see
  // ../../../CLAUDE.md). Subscribing to the SAME media query and closing on its
  // `change` event is the identical behaviour — the reset happens when the
  // viewport crosses the breakpoint — expressed as a subscription, which is the
  // pattern `useIsMobile` itself uses.
  useEffect(() => {
    const mq = window.matchMedia(MOBILE_Q);
    const h = (e: MediaQueryListEvent) => {
      if (!e.matches) setOpen(false);
    };
    mq.addEventListener('change', h);
    return () => mq.removeEventListener('change', h);
  }, []);
  // a solid bar when the menu is open so the dropdown reads against the page
  const solid = scrolled || (isMobile && open);
  return (
    <div
      style={{
        position: 'sticky',
        top: 0,
        zIndex: 50,
        transition: 'background .25s, box-shadow .25s, border-color .25s',
        background: solid ? 'rgba(243,245,248,0.78)' : 'transparent',
        backdropFilter: solid ? 'saturate(180%) blur(14px)' : 'none',
        WebkitBackdropFilter: solid ? 'saturate(180%) blur(14px)' : 'none',
        borderBottom: `1px solid ${solid ? GW.line : 'transparent'}`,
      }}
    >
      <div
        style={{
          maxWidth: GW.maxW,
          margin: '0 auto',
          padding: isMobile ? '0 20px' : '0 32px',
          height: 68,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
        }}
      >
        <a
          href={LANDING_URL}
          style={{ display: 'flex', alignItems: 'center', gap: 11, textDecoration: 'none' }}
        >
          <img src={logoTiny} alt="" style={{ height: 34, width: 'auto', display: 'block' }} />
          <span
            style={{
              fontFamily: GW.sans,
              fontSize: 18,
              fontWeight: 650,
              letterSpacing: -0.4,
              color: GW.ink,
            }}
          >
            {BRAND}
          </span>
        </a>
        {isMobile ? (
          <button
            type="button"
            onClick={() => setOpen((o) => !o)}
            aria-label={open ? 'Close menu' : 'Open menu'}
            aria-expanded={open}
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              width: 42,
              height: 42,
              borderRadius: 11,
              border: `1px solid ${GW.line}`,
              background: GW.surface,
              cursor: 'pointer',
              boxShadow: '0 1px 2px rgba(20,22,40,0.05)',
            }}
          >
            <svg
              width="19"
              height="19"
              viewBox="0 0 18 18"
              fill="none"
              stroke={GW.ink}
              strokeWidth="1.8"
              strokeLinecap="round"
            >
              {open ? <path d="M4 4l10 10M14 4L4 14" /> : <path d="M2.5 5h13M2.5 9h13M2.5 13h13" />}
            </svg>
          </button>
        ) : (
          <div style={{ display: 'flex', alignItems: 'center', gap: 30 }}>
            {NAV_LINKS.map(({ label, href }) => (
              <a
                key={label}
                href={href}
                style={{
                  fontFamily: GW.sans,
                  fontSize: 14.5,
                  fontWeight: 500,
                  color: GW.inkSoft,
                  letterSpacing: -0.1,
                  cursor: 'pointer',
                  textDecoration: 'none',
                }}
              >
                {label}
              </a>
            ))}
            <GWButton label={NAV_CTA} size="sm" arrow={false} href={BOOK_URL} newTab={false} />
          </div>
        )}
      </div>

      {/* mobile dropdown panel — links + CTA, anchored below the 68px bar */}
      {isMobile && open && (
        <div
          style={{
            position: 'absolute',
            top: 68,
            left: 0,
            right: 0,
            zIndex: 49,
            background: 'rgba(243,245,248,0.92)',
            backdropFilter: 'saturate(180%) blur(14px)',
            WebkitBackdropFilter: 'saturate(180%) blur(14px)',
            borderBottom: `1px solid ${GW.line}`,
            boxShadow: '0 18px 40px -24px rgba(20,22,50,0.3)',
          }}
        >
          <div
            style={{
              padding: '12px 20px 20px',
              display: 'flex',
              flexDirection: 'column',
              gap: 4,
            }}
          >
            {NAV_LINKS.map(({ label, href }) => (
              <a
                key={label}
                href={href}
                onClick={() => setOpen(false)}
                style={{
                  fontFamily: GW.sans,
                  fontSize: 16,
                  fontWeight: 500,
                  color: GW.ink,
                  letterSpacing: -0.1,
                  textDecoration: 'none',
                  padding: '12px 4px',
                  borderBottom: `1px solid ${GW.lineSoft}`,
                }}
              >
                {label}
              </a>
            ))}
            <div style={{ marginTop: 14 }} onClick={() => setOpen(false)}>
              <a href={BOOK_URL} style={{ textDecoration: 'none' }}>
                <span
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    width: '100%',
                    boxSizing: 'border-box',
                    fontFamily: GW.sans,
                    fontSize: 15.5,
                    fontWeight: 600,
                    letterSpacing: -0.1,
                    padding: '14px 22px',
                    borderRadius: 12,
                    color: '#fff',
                    background: `linear-gradient(180deg, ${GW.accent}, ${GW.accentDark})`,
                    boxShadow:
                      '0 1px 2px rgba(15,45,95,0.32), 0 8px 22px -6px rgba(30,80,160,0.5), inset 0 1px 0 rgba(255,255,255,0.28)',
                  }}
                >
                  {NAV_CTA}
                </span>
              </a>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
