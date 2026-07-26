// ai-how.jsx — AI page §3. Monitor -> Plan -> Execute, three cards.
// Copy from COPY.ai.how. The sequence is real (each step needs the one before),
// so the steps are numbered; the numbering is information, not decoration.
// Carries [data-motif-section]. Exports AiHowSection to window.

function AiHowSection() {
  const isMobile = useIsMobile();
  const steps = COPY.ai.how.steps;

  return (
    <section
      data-motif-section
      data-screen-label="AI 03 How"
      style={{ position: 'relative', background: 'transparent', padding: isMobile ? '52px 0 92px' : '76px 0 138px' }}
    >
      <div style={{ position: 'relative', zIndex: 1, maxWidth: GW.maxW, margin: '0 auto', padding: isMobile ? '0 20px' : '0 32px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: isMobile ? '1fr' : 'repeat(3, 1fr)', gap: isMobile ? 14 : 20 }}>
          {steps.map((s, i) => (
            <article key={s.key} style={{
              background: 'linear-gradient(180deg, #ffffff, #f5f7fb)',
              border: '1px solid rgba(20,22,40,0.065)',
              borderRadius: 22,
              boxShadow: '0 1px 2px rgba(20,22,40,0.03), 0 22px 50px -30px rgba(20,22,50,0.2), inset 0 1px 0 rgba(255,255,255,0.9)',
              padding: isMobile ? '24px 22px 26px' : '30px 28px 32px',
              display: 'flex', flexDirection: 'column', gap: 12,
            }}>
              <span style={{
                fontFamily: GW.mono, fontSize: 11, fontWeight: 500, letterSpacing: 0.6,
                textTransform: 'uppercase', color: GW.accent,
              }}>{String(i + 1).padStart(2, '0')} {s.name}</span>

              <p style={{
                margin: 0, fontFamily: GW.sans, fontSize: isMobile ? 17 : 18.5, fontWeight: 500,
                lineHeight: 1.42, letterSpacing: -0.3, color: GW.ink, textWrap: 'pretty',
              }}>{s.text}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

window.AiHowSection = AiHowSection;
