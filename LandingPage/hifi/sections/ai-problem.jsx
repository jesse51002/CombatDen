// ai-problem.jsx — AI page §2. One statement, one supporting line.
// Copy from COPY.ai.problem. Carries [data-motif-section]: it is the first stop
// on the motif's chain, so the pinned form is still the spherical spiral here.
// Exports AiProblemSection to window.

function AiProblemSection() {
  const isMobile = useIsMobile();
  const c = COPY.ai.problem;

  return (
    <section
      data-motif-section
      data-screen-label="AI 02 Problem"
      style={{ position: 'relative', overflow: 'hidden', background: 'transparent', padding: isMobile ? '92px 0 0' : '136px 0 0' }}
    >
      <div style={{ position: 'relative', zIndex: 1, maxWidth: GW.maxW, margin: '0 auto', padding: isMobile ? '0 20px' : '0 32px' }}>
        <p data-reveal style={{
          margin: 0, textAlign: 'center', fontFamily: GW.sans, fontWeight: 550,
          fontSize: 'clamp(28px, 3.6vw, 46px)', lineHeight: 1.18, letterSpacing: -1.4,
          color: GW.ink, textWrap: 'balance', maxWidth: '20ch', marginLeft: 'auto', marginRight: 'auto',
        }}>{c.statement}</p>

        <p data-reveal style={{
          '--rd': '120ms',
          margin: isMobile ? '18px auto 0' : '22px auto 0', textAlign: 'center',
          fontFamily: GW.sans, fontWeight: 450, fontSize: 'clamp(16px, 1.8vw, 20px)',
          lineHeight: 1.5, color: GW.inkSoft, maxWidth: '46ch',
        }}>{c.body}</p>
      </div>
    </section>
  );
}

window.AiProblemSection = AiProblemSection;
