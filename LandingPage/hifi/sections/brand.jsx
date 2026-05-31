// brand.jsx — §3 "Your brand, everywhere": centered copy + a rail of themed
// app previews. Each rail card is clickable: picking one sets the GLOBAL active
// theme, so the hero mocks (and every live mock) re-skin to that brand. The rail
// itself stays multi-theme (each card shows its own brand). Copy from COPY.brand.
// Exports BrandSection.

function BrandSection() {
  const { activeId, setTheme } = useTheme();
  const c = COPY.brand;
  const rail = c.rail.map((id) => THEMES.find((t) => t.id === id)).filter(Boolean);
  return (
    <section id="themes" data-screen-label="03 Your brand" style={{ position: 'relative', background: GW.bg, fontFamily: GW.sans, padding: '40px 0 130px' }}>
      <div style={{ textAlign: 'center', padding: '0 32px', maxWidth: GW.maxW, margin: '0 auto' }}>
        <h2 style={{ margin: 0, fontSize: 'clamp(30px,3.4vw,44px)', lineHeight: 1.08, letterSpacing: -1.5, fontWeight: 600, color: GW.ink, textWrap: 'balance' }}>{c.heading}</h2>
        <p style={{ margin: '18px auto 0', maxWidth: 620, fontSize: 'clamp(16px,1.7vw,19px)', lineHeight: 1.5, fontWeight: 450, color: GW.inkSoft, textWrap: 'pretty' }}>
          {c.body}
        </p>
        <div style={{ marginTop: 26 }}><GWButton label={c.button} href={c.themeLibraryUrl} arrow /></div>
      </div>
      {/* infinite, slow, looping marquee — never wraps. The track is two copies
          of the rail; translateX(-50%) lands exactly on the second copy, so the
          loop is seamless. Scrolls continuously; cards stay clickable while moving. */}
      <div style={{ position: 'relative', marginTop: 52, overflow: 'hidden' }}>
        <style>{`
          @keyframes brandMarquee { from { transform: translateX(0); } to { transform: translateX(-50%); } }
          .brand-marquee { animation: brandMarquee 70s linear infinite; will-change: transform; }
          @media (prefers-reduced-motion: reduce) { .brand-marquee { animation: none; } }
        `}</style>
        <div className="brand-marquee" style={{ display: 'flex', gap: 22, width: 'max-content', padding: '24px 0 48px' }}>
          {[...rail, ...rail].map((t, i) => (
            <div key={i} aria-hidden={i >= rail.length ? true : undefined} style={{ flex: '0 0 auto', transform: `translateY(${i % 2 ? 18 : 0}px)` }}>
              <ThemePreview theme={t} width={176} active={t.id === activeId} onClick={() => setTheme(t.id)} />
            </div>
          ))}
        </div>
        {/* edge fades soften where the marquee enters/exits */}
        <div style={{ position: 'absolute', top: 0, bottom: 0, left: 0, width: 120, background: `linear-gradient(to right, ${GW.bg}, transparent)`, pointerEvents: 'none', zIndex: 2 }}></div>
        <div style={{ position: 'absolute', top: 0, bottom: 0, right: 0, width: 120, background: `linear-gradient(to left, ${GW.bg}, transparent)`, pointerEvents: 'none', zIndex: 2 }}></div>
      </div>
    </section>
  );
}

window.BrandSection = BrandSection;
