// chrome.jsx — shared site chrome: primary button, sticky nav, CTA disclaimer.
// Ported from the handoff ds3.jsx. Reads tokens from ds.jsx, the brand name from
// BRAND, and all labels from COPY. Exports GWButton, GWNav, GWDisclaimer.

// Primary / secondary button. label defaults to the demo CTA.
function GWButton({ label = COPY.cta.demo, size = 'md', arrow = true, onClick, href, kind = 'primary', newTab = true }) {
  const pad = size === 'lg' ? '15px 26px' : size === 'sm' ? '9px 16px' : '13px 22px';
  const fs = size === 'lg' ? 16 : size === 'sm' ? 14 : 15;
  const primary = kind === 'primary';
  const Tag = href ? 'a' : 'button';
  const extra = href ? { href, ...(newTab ? { target: '_blank', rel: 'noopener' } : {}) } : { onClick };
  return (
    <Tag {...extra} style={{
      display: 'inline-flex', alignItems: 'center', gap: 9, border: primary ? 'none' : `1px solid ${GW.line}`,
      cursor: 'pointer', whiteSpace: 'nowrap', fontFamily: GW.sans, fontSize: fs, fontWeight: 600,
      letterSpacing: -0.1, color: primary ? '#fff' : GW.ink, padding: pad, borderRadius: 12, textDecoration: 'none',
      background: primary ? `linear-gradient(180deg, ${GW.accent}, ${GW.accentDark})` : GW.surface,
      boxShadow: primary
        ? '0 1px 2px rgba(15,45,95,0.32), 0 8px 22px -6px rgba(30,80,160,0.5), inset 0 1px 0 rgba(255,255,255,0.28)'
        : '0 1px 2px rgba(20,22,40,0.05)',
    }}>
      {label}
      {arrow && <svg width="15" height="15" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M3 8h10M9 4l4 4-4 4"/></svg>}
    </Tag>
  );
}

// Sticky top nav. Becomes a translucent blurred bar on scroll. On mobile
// (useIsMobile) the link list collapses into a hamburger that toggles a dropdown
// panel with the links + CTA (see LandingPage/CLAUDE.md "Mobile responsiveness").
function GWNav() {
  const [scrolled, setScrolled] = React.useState(false);
  const isMobile = useIsMobile();
  const [open, setOpen] = React.useState(false);
  React.useEffect(() => {
    const el = document.querySelector('[data-scroll-root]') || window;
    const target = el === window ? window : el;
    const onScroll = () => {
      const y = el === window ? window.scrollY : el.scrollTop;
      setScrolled(y > 12);
    };
    target.addEventListener('scroll', onScroll, { passive: true });
    onScroll();
    return () => target.removeEventListener('scroll', onScroll);
  }, []);
  // leaving mobile (e.g. rotate to landscape / resize up) closes the menu
  React.useEffect(() => { if (!isMobile) setOpen(false); }, [isMobile]);
  // a solid bar when the menu is open so the dropdown reads against the page
  const solid = scrolled || (isMobile && open);
  return (
    <div style={{
      position: 'sticky', top: 0, zIndex: 50, transition: 'background .25s, box-shadow .25s, border-color .25s',
      background: solid ? 'rgba(243,245,248,0.78)' : 'transparent',
      backdropFilter: solid ? 'saturate(180%) blur(14px)' : 'none',
      WebkitBackdropFilter: solid ? 'saturate(180%) blur(14px)' : 'none',
      borderBottom: `1px solid ${solid ? GW.line : 'transparent'}`,
    }}>
      <div style={{ maxWidth: GW.maxW, margin: '0 auto', padding: isMobile ? '0 20px' : '0 32px', height: 68, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <a href="index.html" style={{ display: 'flex', alignItems: 'center', gap: 11, textDecoration: 'none' }}>
          <img src="assets/landing/logo_tiny.png" alt="" style={{ height: 34, width: 'auto', display: 'block' }} />
          <span style={{ fontFamily: GW.sans, fontSize: 18, fontWeight: 650, letterSpacing: -0.4, color: GW.ink }}>{BRAND}</span>
        </a>
        {isMobile ? (
          <button
            onClick={() => setOpen((o) => !o)}
            aria-label={open ? 'Close menu' : 'Open menu'}
            aria-expanded={open}
            style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', width: 42, height: 42, borderRadius: 11, border: `1px solid ${GW.line}`, background: GW.surface, cursor: 'pointer', boxShadow: '0 1px 2px rgba(20,22,40,0.05)' }}
          >
            <svg width="19" height="19" viewBox="0 0 18 18" fill="none" stroke={GW.ink} strokeWidth="1.8" strokeLinecap="round">
              {open
                ? <path d="M4 4l10 10M14 4L4 14" />
                : <path d="M2.5 5h13M2.5 9h13M2.5 13h13" />}
            </svg>
          </button>
        ) : (
          <div style={{ display: 'flex', alignItems: 'center', gap: 30 }}>
            {COPY.nav.links.map(({ label, href }) => (
              <a key={label} href={href} style={{ fontFamily: GW.sans, fontSize: 14.5, fontWeight: 500, color: GW.inkSoft, letterSpacing: -0.1, cursor: 'pointer', textDecoration: 'none' }}>{label}</a>
            ))}
            <GWButton label={COPY.nav.cta} size="sm" arrow={false} href="#book" newTab={false} />
          </div>
        )}
      </div>

      {/* mobile dropdown panel — links + CTA, anchored below the 68px bar */}
      {isMobile && open && (
        <div style={{ position: 'absolute', top: 68, left: 0, right: 0, zIndex: 49,
          background: 'rgba(243,245,248,0.92)', backdropFilter: 'saturate(180%) blur(14px)', WebkitBackdropFilter: 'saturate(180%) blur(14px)',
          borderBottom: `1px solid ${GW.line}`, boxShadow: '0 18px 40px -24px rgba(20,22,50,0.3)' }}>
          <div style={{ padding: '12px 20px 20px', display: 'flex', flexDirection: 'column', gap: 4 }}>
            {COPY.nav.links.map(({ label, href }) => (
              <a key={label} href={href} onClick={() => setOpen(false)} style={{ fontFamily: GW.sans, fontSize: 16, fontWeight: 500, color: GW.ink, letterSpacing: -0.1, textDecoration: 'none', padding: '12px 4px', borderBottom: `1px solid ${GW.lineSoft}` }}>{label}</a>
            ))}
            <div style={{ marginTop: 14 }} onClick={() => setOpen(false)}>
              <a href="#book" style={{ textDecoration: 'none' }}>
                <span style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', width: '100%', boxSizing: 'border-box',
                  fontFamily: GW.sans, fontSize: 15.5, fontWeight: 600, letterSpacing: -0.1, padding: '14px 22px', borderRadius: 12, color: '#fff',
                  background: `linear-gradient(180deg, ${GW.accent}, ${GW.accentDark})`,
                  boxShadow: '0 1px 2px rgba(15,45,95,0.32), 0 8px 22px -6px rgba(30,80,160,0.5), inset 0 1px 0 rgba(255,255,255,0.28)' }}>
                  {COPY.nav.cta}
                </span>
              </a>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// Small mono disclaimer line with shield icon (used under CTAs).
function GWDisclaimer({ text = COPY.disclaimer, center = true }) {
  return (
    <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, color: GW.inkFaint, justifyContent: center ? 'center' : 'flex-start' }}>
      <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5"><path d="M8 1.5l5.5 2v4c0 3.4-2.4 5.7-5.5 6.9C4.9 13.2 2.5 10.9 2.5 7.5v-4z" strokeLinejoin="round"/><path d="M5.8 8l1.6 1.6L10.4 6" strokeLinecap="round" strokeLinejoin="round"/></svg>
      <span style={{ fontFamily: GW.mono, fontSize: 11.5 }}>{text}</span>
    </div>
  );
}

Object.assign(window, { GWButton, GWNav, GWDisclaimer });
