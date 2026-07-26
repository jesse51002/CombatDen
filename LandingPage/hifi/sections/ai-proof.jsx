// ai-proof.jsx — AI page §4. Four stat cards: what the agent never stops doing.
// Copy and every number from COPY.ai.proof (all illustrative, see the note there
// and the disclaimer under the grid).
//
// The whole section runs ONE 6s loop, and the four cards are phase-shifted by
// 1.5s so only one is ever mid-animation. That is what makes it read as "always
// running" rather than as four things twitching at once.
//
// Each card carries a small 170x62 diagram in a shared drawing language: same box,
// same hairline weights, accent for the measured thing and faint ink for context.
// None of them is a decorative sparkline; each encodes its own card's numbers.
//   Chat        you asked, it answered, it is waiting on the next one
//   Member      cumulative retention saved, climbing across the month
//   Competition 18 posts read with 4 flagged, and a scan that never stops
//   Growth      a year of demand with the slow month picked out, one dot per idea
//
// The resting state of every diagram is the FINISHED picture. The animations only
// exist under `.is-live`, so reduced motion and no-JS both land on something whole
// rather than on a half-drawn chart. Card styling lives in ai.html's <style>.
//
// Carries [data-motif-section]. Exports AiProofSection to window.

const AI_PROOF_CYCLE = 6000;   // one full loop
const AI_PROOF_COUNT = 1200;   // how long a numeral takes to climb
const AI_PROOF_STAGGER = 1500; // gap between cards, so they never fire together

// Splits "$400" into its parts so the count-up animates the digits and keeps the
// format that is already written in the copy.
function aiSplitNum(raw) {
  const m = String(raw).match(/^([^\d]*)([\d,.]+)(.*)$/);
  if (!m) return [raw, null, ''];
  return [m[1], Number(m[2].replace(/,/g, '')), m[3]];
}

// The numeral never settles: it climbs, holds, and starts again on the section's
// shared cycle. Mid-count it sits on the live accent and then eases back to
// accent-dark, which is the "still working" tell.
function AiStatNum({ raw, live, index }) {
  const [prefix, target, suffix] = aiSplitNum(raw);
  const [n, setN] = React.useState(target);
  const [counting, setCounting] = React.useState(false);

  React.useEffect(() => {
    if (target === null) return;
    if (!live) { setN(target); setCounting(false); return; }

    let raf = 0, startTimer = 0, loop = 0;
    const run = () => {
      if (document.hidden) { setN(target); return; }
      setCounting(true);
      const t0 = performance.now();
      const tick = (now) => {
        const p = Math.min(1, (now - t0) / AI_PROOF_COUNT);
        setN(Math.round(target * (1 - Math.pow(1 - p, 3))));
        if (p < 1) raf = requestAnimationFrame(tick);
        else { setN(target); setCounting(false); }
      };
      raf = requestAnimationFrame(tick);
    };

    startTimer = setTimeout(() => { run(); loop = setInterval(run, AI_PROOF_CYCLE); }, index * AI_PROOF_STAGGER);
    return () => { clearTimeout(startTimer); clearInterval(loop); cancelAnimationFrame(raf); };
  }, [live, target, index]);

  const shown = target === null ? raw : `${prefix}${n.toLocaleString()}${suffix}`;
  return <div className={`cd-stat__num${counting ? ' is-counting' : ''}`}>{shown}</div>;
}

// One drawing language across all four: 170x62, hairlines, accent = the measured
// thing. Rendered at rest as the completed picture.
function AiViz({ kind }) {
  const box = { viewBox: '0 0 170 62', fill: 'none', 'aria-hidden': 'true' };

  if (kind === 'chat') {
    return (
      <svg {...box}>
        <rect x="82" y="0" width="86" height="18" rx="9" className="cd-viz-accent" />
        <rect x="2" y="22" width="112" height="18" rx="9" fill="#eef1f6" stroke="rgba(20,22,30,0.09)" strokeWidth="1" />
        <rect x="92" y="44" width="76" height="18" rx="9" stroke="#2A67BD" strokeOpacity="0.4" strokeWidth="1.2" strokeDasharray="4 3.5" />
        <rect className="cd-viz__caret" x="101" y="48" width="1.8" height="10" rx="0.9" />
      </svg>
    );
  }

  if (kind === 'member') {
    return (
      <svg {...box}>
        <defs>
          <linearGradient id="cdMemArea" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#2A67BD" stopOpacity="0.22" />
            <stop offset="100%" stopColor="#2A67BD" stopOpacity="0" />
          </linearGradient>
        </defs>
        <path className="cd-viz__area" d="M6 50 L34 44 L62 40 L90 28 L118 22 L146 14 L164 8 L164 54 L6 54 Z" fill="url(#cdMemArea)" />
        <path className="cd-viz__line" d="M6 50 L34 44 L62 40 L90 28 L118 22 L146 14 L164 8" />
        <circle className="cd-viz__halo" cx="164" cy="8" r="3.5" />
        <circle className="cd-viz-accent" cx="164" cy="8" r="3.2" />
      </svg>
    );
  }

  if (kind === 'competition') {
    // 18 bars, the 4 flagged ones raised. The sweep is the scan passing over.
    const flagged = new Set([2, 7, 11, 16]);
    return (
      <svg {...box}>
        <defs>
          <linearGradient id="cdCmpSweep" x1="0" y1="0" x2="1" y2="0">
            <stop offset="0%" stopColor="#2A67BD" stopOpacity="0" />
            <stop offset="60%" stopColor="#2A67BD" stopOpacity="0.16" />
            <stop offset="100%" stopColor="#2A67BD" stopOpacity="0" />
          </linearGradient>
        </defs>
        {Array.from({ length: 18 }, (_, i) => {
          const hit = flagged.has(i);
          return (
            <rect key={i} x={4 + i * 9.2} y={hit ? 18 : 34} width="3" height={hit ? 30 : 14} rx="1.5"
              className={hit ? 'cd-viz-accent' : 'cd-viz-faint'} />
          );
        })}
        <path className="cd-viz-rule" d="M2 52.5 H168" strokeLinecap="round" />
        <rect className="cd-viz__sweep" x="-32" y="8" width="32" height="46" fill="url(#cdCmpSweep)" />
      </svg>
    );
  }

  // growth: twelve months of demand, the slow one picked out, one dot per idea
  const months = [26, 30, 24, 22, 28, 34, 38, 42, 36, 28, 22, 18];
  const SLOW = 7;
  return (
    <svg {...box}>
      {months.map((y, i) => (
        <rect key={i} x={4 + i * 13.6} y={y} width="8" height={52 - y} rx="2.5"
          className={i === SLOW ? 'cd-viz-accent-soft' : 'cd-viz-faint'}
          {...(i === SLOW ? { stroke: '#2A67BD', strokeOpacity: 0.5, strokeWidth: 1 } : {})} />
      ))}
      <path className="cd-viz-rule" d="M2 55 H168" strokeLinecap="round" />
      {[[103.2, 34, 0.1], [130.4, 20, 0.3], [157.6, 10, 0.5]].map(([cx, cy, d]) => (
        <circle key={cx} className="cd-viz__mark" style={{ '--md': `${d}s` }} cx={cx} cy={cy} r="2.6" />
      ))}
    </svg>
  );
}

// The two-beat "it saw X, so it did Y" list. The second beat carries a tick, so
// the outcome is distinguishable from the observation at a glance.
function AiSteps({ steps }) {
  return (
    <ul className="cd-stat__steps">
      {steps.map((text, i) => (
        <li key={text} className="cd-stat__step" style={i ? { '--sd': '0.62s' } : undefined}>
          {i === 0 ? (
            <svg width="13" height="13" viewBox="0 0 14 14" fill="none" aria-hidden="true">
              <circle cx="7" cy="7" r="5.2" stroke={GW.inkFaint} strokeWidth="1.3" />
              <circle cx="7" cy="7" r="1.7" fill={GW.inkFaint} />
            </svg>
          ) : (
            <svg width="13" height="13" viewBox="0 0 14 14" fill="none" aria-hidden="true">
              <circle cx="7" cy="7" r="6.35" fill={GW.accentSoft} />
              <path d="M4.3 7.15 6.2 9.05 9.8 5.2" stroke={GW.accentDark} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          )}
          <span>{text}</span>
        </li>
      ))}
    </ul>
  );
}

// The chat card shows the exchange itself rather than describing it: you ask, it
// thinks, it answers with the time it took. Mock furniture, like the phone mocks
// on the landing page, so the dialogue lives here and not in COPY.
function AiChatExchange() {
  return (
    <div className="cd-cx-wrap" role="img"
      aria-label="Example exchange: you ask for last month's revenue by plan, the agent answers in 12 seconds.">
      <div className="cd-cx cd-cx--you"><span className="cd-cx__b">Last month's revenue by plan?</span></div>
      <div className="cd-cx cd-cx--wait" aria-hidden="true">
        <span className="cd-cx__av" />
        <span className="cd-cx__b cd-cx__dots"><i /><i /><i /></span>
      </div>
      <div className="cd-cx cd-cx--ai">
        <span className="cd-cx__av" />
        <span className="cd-cx__b">$18,240. Premium is 62%.<span className="cd-cx__meta">12s</span></span>
      </div>
    </div>
  );
}

function AiProofSection() {
  const isMobile = useIsMobile();
  const c = COPY.ai.proof;
  const ref = React.useRef(null);
  const [live, setLive] = React.useState(false);

  // The loop runs only while the section is on screen, so a page left open in a
  // background tab is not animating to nobody.
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
      data-screen-label="AI 04 Proof"
      className={live ? 'cd-proof is-live' : 'cd-proof'}
      style={{ position: 'relative', background: 'transparent', padding: isMobile ? '92px 0 96px' : '128px 0 132px' }}
    >
      <GWGlow style={{ top: 40, left: '50%', transform: 'translateX(-50%)', width: 1000, height: 620, background: `radial-gradient(50% 50% at 50% 50%, ${GW.accentGlow}, transparent 72%)` }} />

      <div style={{ position: 'relative', zIndex: 1, maxWidth: GW.maxW, margin: '0 auto', padding: isMobile ? '0 20px' : '0 32px' }}>
        <h2 data-reveal style={{
          margin: 0, fontFamily: GW.sans, fontWeight: 600,
          fontSize: 'clamp(30px, 3.4vw, 44px)', lineHeight: 1.08, letterSpacing: -1.5,
          color: GW.ink, textWrap: 'balance', maxWidth: '18ch',
        }}>{c.heading}</h2>

        <div style={{
          marginTop: isMobile ? 36 : 52,
          display: 'grid', gridTemplateColumns: isMobile ? '1fr' : 'repeat(2, 1fr)',
          gap: isMobile ? 14 : 20,
        }}>
          {c.cards.map((card, i) => (
            <article key={card.key} className="cd-stat" data-reveal
              style={{ '--cd': `${i * 1.5}s`, '--rd': `${i * 90}ms`, '--hue': AGENT_HUES[card.key] }}>
              {/* The card's title, and the same handle the §5 log uses for this
                  channel. Naming it the same way in both places, in the same hue,
                  is what makes the log legible later: by then you already know
                  what @member means. */}
              <h3 className="cd-stat__cat">@{card.key}</h3>

              <div className="cd-stat__row">
                <AiStatNum raw={card.num} live={live} index={i} />
                <div className="cd-stat__viz"><AiViz kind={card.key} /></div>
              </div>
              <p className="cd-stat__numlabel">{card.numLabel}</p>

              {card.key === 'chat' ? <AiChatExchange /> : <AiSteps steps={card.steps} />}

              <dl className="cd-stat__secondary">
                {card.secondary.map(([k, v]) => (
                  <div key={k}><dt>{k}</dt><dd>{v}</dd></div>
                ))}
              </dl>

              <div className="cd-stat__status">
                <span className="cd-pulse" aria-hidden="true" />
                <span>{card.status}</span>
              </div>
            </article>
          ))}
        </div>

        <p className="cd-proof__note" data-reveal>Illustrative examples. Not real usage data.</p>
      </div>
    </section>
  );
}

window.AiProofSection = AiProofSection;
