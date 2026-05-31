// why.jsx — §7 "Why it matters": two ROI stats that count up on scroll-in.
// Honors the "show the math" principle. Copy from COPY.why. Exports WhyMattersSection.

function useInView(ref) {
  const [seen, setSeen] = React.useState(false);
  React.useEffect(() => {
    const el = ref.current; if (!el) return;
    const io = new IntersectionObserver((e) => { if (e[0].isIntersecting) { setSeen(true); io.disconnect(); } }, { threshold: 0.2 });
    io.observe(el); return () => io.disconnect();
  }, []);
  return seen;
}

function useCountUp(target, run, dur = 1500) {
  const [v, setV] = React.useState(0);
  React.useEffect(() => {
    if (!run) return;
    let raf; const t0 = performance.now();
    const ease = (p) => 1 - Math.pow(1 - p, 3);
    const tick = (t) => { const p = Math.min(1, (t - t0) / dur); setV(target * ease(p)); if (p < 1) raf = requestAnimationFrame(tick); };
    raf = requestAnimationFrame(tick); return () => cancelAnimationFrame(raf);
  }, [run, target]);
  return v;
}

function Stat({ prefix = '', value, suffix = '', format, line, math, run }) {
  const v = useCountUp(value, run);
  const shown = format ? format(v) : Math.round(v).toString();
  return (
    <div style={{ textAlign: 'center', padding: '0 24px' }}>
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'center', gap: 2, color: GW.accentDark }}>
        <span style={{ fontSize: 'clamp(52px,8vw,104px)', fontWeight: 700, letterSpacing: -4, lineHeight: 1, fontVariantNumeric: 'tabular-nums' }}>{prefix}{shown}{suffix}</span>
      </div>
      <p style={{ margin: '22px auto 0', maxWidth: 360, fontSize: 'clamp(17px,1.9vw,21px)', lineHeight: 1.45, fontWeight: 500, color: GW.ink, letterSpacing: -0.2, textWrap: 'balance' }}>{line}</p>
      {math && (
        <div style={{ marginTop: 14, fontFamily: GW.mono, fontSize: 12, letterSpacing: 0.3, color: GW.inkFaint }}>{math}</div>
      )}
    </div>
  );
}

function WhyMattersSection() {
  const ref = React.useRef(null);
  const run = useInView(ref);
  const c = COPY.why;
  return (
    <section ref={ref} data-screen-label="07 Why it matters" style={{ width: '100%', background: GW.bg, fontFamily: GW.sans, position: 'relative', overflow: 'visible' }}>
      <GWGlow style={{ top: -160, left: '50%', transform: 'translateX(-50%)', width: 880, height: 480, background: `radial-gradient(50% 50% at 50% 50%, ${GW.accentGlow}, transparent 72%)` }} />
      <div style={{ position: 'relative', zIndex: 1, maxWidth: GW.maxW, margin: '0 auto', padding: '100px 32px 108px' }}>
        <h2 style={{ margin: 0, textAlign: 'center', fontSize: 'clamp(30px,3.4vw,44px)', lineHeight: 1.08, letterSpacing: -1.5, fontWeight: 600, color: GW.ink, textWrap: 'balance' }}>{c.heading}</h2>

        <div style={{ marginTop: 72, display: 'grid', gridTemplateColumns: '1fr 1fr', alignItems: 'center', gap: 0, maxWidth: 920, marginLeft: 'auto', marginRight: 'auto' }}>
          <Stat value={c.stats[0].value} suffix={c.stats[0].suffix} run={run} line={c.stats[0].line} />
          <Stat prefix={c.stats[1].prefix} value={c.stats[1].value} run={run}
            format={(v) => Math.round(v).toLocaleString('en-US')}
            line={c.stats[1].line} />
        </div>
      </div>
    </section>
  );
}

window.WhyMattersSection = WhyMattersSection;
