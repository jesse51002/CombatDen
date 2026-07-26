// ai-how.jsx — AI page §3. Monitor -> Plan -> Execute, three cards.
// Copy from COPY.ai.how. The sequence is real (each step needs the one before),
// so the steps are numbered; the numbering is information, not decoration.
//
// Each card shows its own verb working rather than an icon standing for it:
//   Monitor  five bars reading a live signal
//   Plan     three lines drafting themselves in
//   Execute  a ring running to completion, then a tick
//
// They are small, quiet, and staggered across the row (--sd per card, --gd per
// element inside it) so the three never pulse in unison. Every resting state is
// the finished shape, so reduced motion and no-JS land on something whole. The
// glyph CSS lives in ai.html's <style>.
//
// Carries [data-motif-section]. Exports AiHowSection to window.

// Monitor: a live signal, each bar breathing on its own offset.
function AiGlyphMonitor() {
  const bars = [[1, 18, 14, 0], [10, 6, 26, 0.16], [19, 12, 20, 0.32], [28, 2, 30, 0.48], [37, 15, 17, 0.64]];
  return (
    <svg width="44" height="34" viewBox="0 0 44 34" fill="none" aria-hidden="true">
      {bars.map(([x, y, h, d]) => (
        <rect key={x} className="cd-sig cd-glyph-accent" style={{ '--gd': `${d}s` }}
          x={x} y={y} width="3.4" height={h} rx="1.7" opacity="0.6" />
      ))}
    </svg>
  );
}

// Plan: three lines drafting in from the left, each with its own bullet.
function AiGlyphPlan() {
  const lines = [[3, 34, 0], [14, 42, 0.28], [25, 26, 0.56]];
  return (
    <svg width="44" height="34" viewBox="0 0 50 34" fill="none" aria-hidden="true">
      {lines.map(([y, w, d]) => (
        <React.Fragment key={y}>
          <rect className="cd-draft cd-glyph-accent" style={{ '--gd': `${d}s` }} x="8" y={y} width={w} height="6" rx="3" opacity="0.55" />
          <rect className="cd-draft cd-glyph-faint" style={{ '--gd': `${d}s` }} x="0" y={y} width="5" height="6" rx="2" />
        </React.Fragment>
      ))}
    </svg>
  );
}

// Execute: the ring runs all the way round, then the tick draws.
function AiGlyphExecute() {
  return (
    <svg width="34" height="34" viewBox="0 0 34 34" fill="none" aria-hidden="true">
      <circle cx="17" cy="17" r="12.1" stroke={GW.line} strokeWidth="2.4" />
      <path className="cd-run__arc" d="M17 4.9a12.1 12.1 0 1 1-8.56 3.54" />
      <path className="cd-run__tick" d="M11.7 17.2 15.4 20.9 22.4 13.6" />
    </svg>
  );
}

const AI_GLYPHS = { monitor: AiGlyphMonitor, plan: AiGlyphPlan, execute: AiGlyphExecute };

function AiHowSection() {
  const isMobile = useIsMobile();
  const steps = COPY.ai.how.steps;
  const ref = React.useRef(null);
  const [live, setLive] = React.useState(false);

  // The glyphs loop only while the row is on screen.
  React.useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(
      (entries) => setLive(entries[0].isIntersecting),
      { rootMargin: IN_VIEW_MARGIN, threshold: 0 }
    );
    io.observe(el);
    return () => io.disconnect();
  }, []);

  return (
    <section
      ref={ref}
      data-motif-section
      data-screen-label="AI 03 How"
      className={live ? 'cd-how is-live' : 'cd-how'}
      style={{ position: 'relative', background: 'transparent', padding: isMobile ? '52px 0 92px' : '76px 0 138px' }}
    >
      <div style={{ position: 'relative', zIndex: 1, maxWidth: GW.maxW, margin: '0 auto', padding: isMobile ? '0 20px' : '0 32px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: isMobile ? '1fr' : 'repeat(3, 1fr)', gap: isMobile ? 14 : 20 }}>
          {steps.map((s, i) => {
            const Glyph = AI_GLYPHS[s.key];
            return (
              <article key={s.key} className="cd-step" data-reveal
                style={{ '--rd': `${i * 90}ms`, '--sd': `${i * 0.5}s` }}>
                <div className="cd-step__top">
                  <span className="cd-step__n">{String(i + 1).padStart(2, '0')}</span>
                  <span className="cd-step__live">{Glyph ? <Glyph /> : null}</span>
                </div>
                <div className="cd-step__rule" />
                <h3>{s.name}</h3>
                <p>{s.text}</p>
              </article>
            );
          })}
        </div>
      </div>
    </section>
  );
}

window.AiHowSection = AiHowSection;
