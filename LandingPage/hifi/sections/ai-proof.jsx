// ai-proof.jsx — AI page §4. Four stat cards: what the agent works on.
// Copy and every number from COPY.ai.proof (all illustrative, see the note there).
//
// The numerals count up once the section reveals, reusing IN_VIEW_MARGIN so they
// fire at the same scroll point as every other animation on the site. A numeral
// like "$400" counts on its digits and keeps its prefix, so the format is read off
// the copy rather than duplicated here as a flag.
//
// Carries [data-motif-section]. Exports AiProofSection to window.

// Splits "$400" into ["$", 400, ""] so the count-up animates the digits only.
function aiSplitNum(raw) {
  const m = String(raw).match(/^([^\d]*)([\d,.]+)(.*)$/);
  if (!m) return [raw, null, ''];
  return [m[1], Number(m[2].replace(/,/g, '')), m[3]];
}

function AiStatNum({ raw, run }) {
  const [prefix, target, suffix] = aiSplitNum(raw);
  const [n, setN] = React.useState(target === null ? null : 0);

  React.useEffect(() => {
    if (!run || target === null) return;
    let raf = 0;
    const start = performance.now();
    const DUR = 1100;
    const tick = (now) => {
      const p = Math.min(1, (now - start) / DUR);
      // exponential ease-out: fast off the mark, settles onto the real figure
      setN(Math.round(target * (1 - Math.pow(1 - p, 3))));
      if (p < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [run, target]);

  const shown = target === null ? raw : `${prefix}${n.toLocaleString()}${suffix}`;
  return (
    <span style={{
      fontFamily: GW.sans, fontWeight: 700, fontSize: 'clamp(40px, 4.6vw, 58px)',
      lineHeight: 1, letterSpacing: -2.4, color: GW.accentDark,
      fontVariantNumeric: 'tabular-nums',
    }}>{shown}</span>
  );
}

function AiProofSection() {
  const isMobile = useIsMobile();
  const c = COPY.ai.proof;
  const ref = React.useRef(null);
  const [run, setRun] = React.useState(false);

  React.useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver((entries) => {
      // latch on: the figures settle once and are not replayed on the way back up
      if (entries[0].isIntersecting) { setRun(true); io.disconnect(); }
    }, { rootMargin: IN_VIEW_MARGIN, threshold: 0 });
    io.observe(el);
    return () => io.disconnect();
  }, []);

  return (
    <section
      ref={ref}
      data-motif-section
      data-screen-label="AI 04 Proof"
      style={{ position: 'relative', background: 'transparent', padding: isMobile ? '92px 0 96px' : '128px 0 132px' }}
    >
      <GWGlow style={{ top: 40, left: '50%', transform: 'translateX(-50%)', width: 1000, height: 620, background: `radial-gradient(50% 50% at 50% 50%, ${GW.accentGlow}, transparent 72%)` }} />

      <div style={{ position: 'relative', zIndex: 1, maxWidth: GW.maxW, margin: '0 auto', padding: isMobile ? '0 20px' : '0 32px' }}>
        <h2 style={{
          margin: '0 0 auto', fontFamily: GW.sans, fontWeight: 600,
          fontSize: 'clamp(30px, 3.4vw, 44px)', lineHeight: 1.08, letterSpacing: -1.5,
          color: GW.ink, textWrap: 'balance', maxWidth: '18ch',
        }}>{c.heading}</h2>

        <div style={{
          marginTop: isMobile ? 36 : 52,
          display: 'grid', gridTemplateColumns: isMobile ? '1fr' : 'repeat(2, 1fr)',
          gap: isMobile ? 14 : 20,
        }}>
          {c.cards.map((card) => (
            <article key={card.key} style={{
              background: 'linear-gradient(180deg, #ffffff, #f5f7fb)',
              border: '1px solid rgba(20,22,40,0.065)',
              borderRadius: 22,
              boxShadow: '0 1px 2px rgba(20,22,40,0.03), 0 22px 50px -30px rgba(20,22,50,0.2), inset 0 1px 0 rgba(255,255,255,0.9)',
              padding: isMobile ? '24px 22px 24px' : '30px 30px 28px',
              display: 'flex', flexDirection: 'column', gap: 18,
            }}>
              <span style={{
                alignSelf: 'flex-start', fontFamily: GW.mono, fontSize: 10.5, fontWeight: 500,
                letterSpacing: 0.6, textTransform: 'uppercase', color: GW.accent,
                background: GW.accentSoft, padding: '4px 8px', borderRadius: 999,
              }}>{card.tag}</span>

              <div style={{ display: 'flex', flexDirection: 'column', gap: 7 }}>
                <AiStatNum raw={card.num} run={run} />
                <span style={{ fontFamily: GW.sans, fontSize: 14.5, fontWeight: 450, color: GW.inkSoft, letterSpacing: -0.1 }}>{card.numLabel}</span>
              </div>

              <p style={{
                margin: 0, fontFamily: GW.sans, fontSize: 15, fontWeight: 450, lineHeight: 1.5,
                color: GW.ink, textWrap: 'pretty',
                paddingTop: 16, borderTop: `1px solid ${GW.lineSoft}`,
              }}>{card.action}</p>

              <dl style={{ margin: 0, display: 'flex', flexWrap: 'wrap', gap: '10px 22px' }}>
                {card.secondary.map(([k, v]) => (
                  <div key={k} style={{ display: 'flex', alignItems: 'baseline', gap: 7 }}>
                    <dt style={{ fontFamily: GW.mono, fontSize: 10.5, letterSpacing: 0.4, textTransform: 'uppercase', color: GW.inkFaint }}>{k}</dt>
                    <dd style={{ margin: 0, fontFamily: GW.sans, fontSize: 14, fontWeight: 600, color: GW.ink, fontVariantNumeric: 'tabular-nums' }}>{v}</dd>
                  </div>
                ))}
              </dl>

              <div style={{ marginTop: 'auto', paddingTop: 4, display: 'flex', alignItems: 'center', gap: 8 }}>
                <span className="cd-pulse" style={{ width: 7, height: 7, borderRadius: 999, background: GW.accent, flex: 'none' }} />
                <span style={{ fontFamily: GW.mono, fontSize: 11, letterSpacing: 0.3, color: GW.inkFaint }}>{card.status}</span>
              </div>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

window.AiProofSection = AiProofSection;
