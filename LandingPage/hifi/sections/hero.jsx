// hero.jsx — §1 Hero: editorial headline, gradient mesh, phone trio.
// Adds the ThemeSwitcher swatch row just above the phones so picking a brand
// visibly re-skins all three mocks. Copy from COPY.hero. Exports HeroSection.

function HeroSection() {
  return (
    <section data-screen-label="01 Hero" style={{ position: 'relative', overflow: 'hidden', background: GW.bg, fontFamily: GW.sans, marginTop: -68 }}>
      {/* gradient mesh */}
      <GWGlow style={{ top: -300, left: -160, width: 820, height: 760, background: `radial-gradient(50% 50% at 50% 50%, ${GW.accentGlow}, transparent 70%)` }} />
      <GWGlow style={{ top: -240, right: -180, width: 760, height: 740, background: `radial-gradient(50% 50% at 50% 50%, ${GW.cyanGlow}, transparent 70%)` }} />
      <GWDotGrid />

      <div style={{ position: 'relative', zIndex: 3, display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', padding: '92px 32px 0', maxWidth: 940, margin: '0 auto' }}>
        <h1 style={{ margin: 0, fontSize: 'clamp(40px, 6vw, 68px)', lineHeight: 1.0, fontWeight: 600, letterSpacing: -2.4, color: GW.ink, maxWidth: 840, textWrap: 'balance' }}>
          {COPY.hero.headline}
        </h1>
        <p style={{ margin: '24px 0 0', fontSize: 'clamp(17px, 2vw, 20px)', lineHeight: 1.5, color: GW.inkSoft, maxWidth: 600, fontWeight: 450, textWrap: 'pretty' }}>
          {COPY.hero.subline}
        </p>
        <div style={{ marginTop: 30 }}><GWButton size="lg" href="#book" /></div>
        <div style={{ marginTop: 18 }}><GWDisclaimer /></div>
      </div>

      {/* phone trio: tops fully visible, bottoms bleed off & fade into next section.
          The phones show the active brand theme (set in §3 Your brand). */}
      <div style={{ position: 'relative', zIndex: 2, marginTop: 60 }}>
        <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'flex-start', height: 430, overflow: 'hidden' }}>
          <div style={{ transform: 'translateY(56px)', marginRight: -44, zIndex: 1 }}>
            <PhoneMock width={250} tilt="left" glow={false} />
          </div>
          <div style={{ zIndex: 2 }}>
            <PhoneMock width={300} tilt="none" glow={true} />
          </div>
          <div style={{ transform: 'translateY(56px)', marginLeft: -44, zIndex: 1 }}>
            <PhoneMock width={250} tilt="right" glow={false} />
          </div>
        </div>
        {/* soft fade so the phones dissolve into the next section */}
        <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 150, background: `linear-gradient(to top, ${GW.bg} 12%, transparent)`, pointerEvents: 'none', zIndex: 3 }}></div>
      </div>
    </section>
  );
}

window.HeroSection = HeroSection;
