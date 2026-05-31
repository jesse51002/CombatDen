// chrome.jsx — shared site chrome: primary button, sticky nav, CTA disclaimer.
// Ported from the handoff ds3.jsx. Reads tokens from ds.jsx, the brand name from
// BRAND, and all labels from COPY. Exports GWButton, GWNav, GWDisclaimer.

// Primary / secondary button. label defaults to the demo CTA.
function GWButton({ label = COPY.cta.demo, size = 'md', arrow = true, onClick, href, kind = 'primary' }) {
  const pad = size === 'lg' ? '15px 26px' : size === 'sm' ? '9px 16px' : '13px 22px';
  const fs = size === 'lg' ? 16 : size === 'sm' ? 14 : 15;
  const primary = kind === 'primary';
  const Tag = href ? 'a' : 'button';
  const extra = href ? { href, target: '_blank', rel: 'noopener' } : { onClick };
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

// Sticky top nav. Becomes a translucent blurred bar on scroll.
function GWNav() {
  const [scrolled, setScrolled] = React.useState(false);
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
  return (
    <div style={{
      position: 'sticky', top: 0, zIndex: 50, transition: 'background .25s, box-shadow .25s, border-color .25s',
      background: scrolled ? 'rgba(243,245,248,0.78)' : 'transparent',
      backdropFilter: scrolled ? 'saturate(180%) blur(14px)' : 'none',
      WebkitBackdropFilter: scrolled ? 'saturate(180%) blur(14px)' : 'none',
      borderBottom: `1px solid ${scrolled ? GW.line : 'transparent'}`,
    }}>
      <div style={{ maxWidth: GW.maxW, margin: '0 auto', padding: '0 32px', height: 68, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <a href="index.html" style={{ display: 'flex', alignItems: 'center', gap: 11, textDecoration: 'none' }}>
          <div style={{ width: 30, height: 30, borderRadius: 9, background: `linear-gradient(150deg, ${GW.accent}, ${GW.accentDark})`, display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 2px 6px rgba(30,80,160,0.35)' }}>
            <span style={{ fontFamily: GW.mono, fontSize: 8, color: 'rgba(255,255,255,0.92)', letterSpacing: 0.2 }}>{COPY.nav.logoMark}</span>
          </div>
          <span style={{ fontFamily: GW.sans, fontSize: 18, fontWeight: 650, letterSpacing: -0.4, color: GW.ink }}>{BRAND}</span>
        </a>
        <div style={{ display: 'flex', alignItems: 'center', gap: 30 }}>
          {COPY.nav.links.map(({ label, href }) => (
            <a key={label} href={href} style={{ fontFamily: GW.sans, fontSize: 14.5, fontWeight: 500, color: GW.inkSoft, letterSpacing: -0.1, cursor: 'pointer', textDecoration: 'none' }}>{label}</a>
          ))}
          <GWButton label={COPY.nav.cta} size="sm" arrow={false} href="#book" />
        </div>
      </div>
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
