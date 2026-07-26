// ai-hero.jsx — AI page §1. Centred hero: headline, subline, CTA, reassurance.
// Copy from COPY.ai.hero. The [data-motif-hero] div is the canvas host motif.js
// looks for; it stays empty in the markup and is filled after mount.
// Exports AiHeroSection to window.

function AiHeroSection() {
  const isMobile = useIsMobile();
  const c = COPY.ai.hero;

  return (
    <section
      data-screen-label="AI 01 Hero"
      style={{
        position: 'relative', overflow: 'hidden', background: 'transparent',
        // pulls the hero up under the sticky 68px nav so the glow starts at the top
        marginTop: -68,
      }}
    >
      <GWGlow style={{ top: -300, left: -160, width: 820, height: 760, background: `radial-gradient(50% 50% at 50% 50%, ${GW.accentGlow}, transparent 70%)` }} />
      <GWGlow style={{ top: -240, right: -180, width: 760, height: 740, background: `radial-gradient(50% 50% at 50% 50%, ${GW.cyanGlow}, transparent 70%)` }} />
      <GWDotGrid />
      <div data-motif-hero className="cd-motif" aria-hidden="true" />

      <div style={{
        position: 'relative', zIndex: 3, display: 'flex', flexDirection: 'column',
        alignItems: 'center', textAlign: 'center', justifyContent: 'center',
        minHeight: isMobile ? 0 : 'min(78vh, 760px)',
        padding: isMobile ? '126px 20px 92px' : '168px 32px 116px',
        maxWidth: 1000, margin: '0 auto',
      }}>
        <h1 data-reveal style={{
          margin: 0, fontFamily: GW.sans, fontWeight: 600,
          fontSize: 'clamp(40px, 6vw, 68px)', lineHeight: 1.0, letterSpacing: -2.4,
          color: GW.ink, textWrap: 'balance', maxWidth: isMobile ? 'none' : '15.5ch',
        }}>{c.headline}</h1>

        <p data-reveal style={{
          '--rd': '110ms',
          margin: isMobile ? '22px 0 0' : '26px 0 0', fontFamily: GW.sans, fontWeight: 450,
          fontSize: 'clamp(16px, 1.8vw, 20px)', lineHeight: 1.5, color: GW.inkSoft,
          maxWidth: isMobile ? '30ch' : '46ch',
        }}>{c.subline}</p>

        <div data-reveal style={{ '--rd': '200ms', marginTop: isMobile ? 30 : 36 }}>
          <GWButton label={COPY.cta.demo} size="lg" href="#book" newTab={false} />
        </div>

        <div data-reveal style={{ '--rd': '280ms', marginTop: 22 }}>
          <GWDisclaimer />
        </div>
      </div>
    </section>
  );
}

window.AiHeroSection = AiHeroSection;
