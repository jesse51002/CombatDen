// loyalty.jsx — §6 Loyalty engine: an auto-cycling points loop + a 3-card reward
// carousel (focused centre, two peeking sides, prev/next, benefit caption).
// Copy/data from COPY.loyalty. Exports LoyaltySection.

const rlCard = {
  background: 'linear-gradient(180deg, #ffffff, #f5f7fb)',
  border: '1px solid rgba(20,22,40,0.065)',
  borderRadius: 24,
  boxShadow: '0 1px 2px rgba(20,22,40,0.03), 0 22px 50px -30px rgba(20,22,50,0.2), inset 0 1px 0 rgba(255,255,255,0.9)',
};

const loopIcons = {
  attend: (c, s = 20) => (<svg width={s} height={s} viewBox="0 0 20 20" fill="none" stroke={c} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="4" width="14" height="13" rx="2.5"/><path d="M3 8h14M7 2.5v3M13 2.5v3M7.5 12.5l1.6 1.6 3-3.2"/></svg>),
  earn: (c, s = 20) => (<svg width={s} height={s} viewBox="0 0 20 20" fill={c}><path d="M10 1.5l2.2 5.9 5.8.4-4.5 3.7 1.5 5.6L10 13.8 4.5 17.1l1.5-5.6L1.5 7.8l5.8-.4z"/></svg>),
  redeem: (c, s = 20) => (<svg width={s} height={s} viewBox="0 0 20 20" fill="none" stroke={c} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><path d="M3 9h14v8H3zM2 5.5h16V9H2zM10 5.5V17M10 5.5S8.5 2.5 6.5 2.5 4.5 5.5 10 5.5zM10 5.5S11.5 2.5 13.5 2.5 15.5 5.5 10 5.5z"/></svg>),
  loyal: (c, s = 20) => (<svg width={s} height={s} viewBox="0 0 20 20" fill={c}><path d="M10 17.5l-1.2-1.05C4.6 12.7 2 10.36 2 7.5 2 5.42 3.42 4 5.5 4c1.17 0 2.3.55 3 1.42C9.2 4.55 10.33 4 11.5 4 13.58 4 15 5.42 15 7.5c0 2.86-2.6 5.2-6.8 8.95z"/></svg>),
};

const rewardIcons = {
  shirt: (c, s = 30) => (<svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"><path d="M8 3l4 3 4-3 5 4-3 3-1-1v9H7v-9l-1 1-3-3z"/></svg>),
  friend: (c, s = 30) => (<svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"><circle cx="8.5" cy="8" r="3"/><path d="M2.5 19a6 6 0 0112 0"/><path d="M16 5.5a3 3 0 010 5.8M16.5 13.5a6 6 0 015 5.5"/></svg>),
  training: (c, s = 30) => (<svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"><path d="M6.5 6.5l11 11M4 9l-2 2 3 3M9 4l2-2 3 3M15 20l2-2M4 15l-2 2 3 3 2-2M20 9l2-2-3-3-2 2"/></svg>),
};

// the loyalty loop (centered focal)
function PointsLoop() {
  const [active, setActive] = React.useState(0);
  const steps = COPY.loyalty.loop;
  React.useEffect(() => {
    const t = setInterval(() => setActive((a) => (a + 1) % steps.length), 950);
    return () => clearInterval(t);
  }, []);
  return (
    <div style={{ maxWidth: 800, margin: '0 auto' }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'center', gap: 6 }}>
        {steps.map((s, i) => {
          const on = i === active;
          return (
            <React.Fragment key={s.key}>
              <div style={{ width: 132, display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', gap: 12, transition: 'transform .4s ease', transform: on ? 'translateY(-4px)' : 'none' }}>
                <div style={{ position: 'relative', width: 66, height: 66, borderRadius: 19, display: 'flex', alignItems: 'center', justifyContent: 'center', transition: 'all .4s ease',
                  background: on ? GW.accentSoft : '#fff', border: `1px solid ${on ? GW.accent + '55' : GW.line}`, boxShadow: on ? `0 12px 26px -10px ${GW.accent}66` : '0 1px 2px rgba(20,22,40,0.05)' }}>
                  {loopIcons[s.key](on ? GW.accentDark : GW.inkSoft, 26)}
                  {s.badge && (
                    <div style={{ position: 'absolute', top: -10, right: -14, fontFamily: GW.mono, fontSize: 11, fontWeight: 600, color: '#fff', background: GW.accent, padding: '3px 7px', borderRadius: 999, boxShadow: `0 4px 10px ${GW.accent}66` }}>{s.badge}</div>
                  )}
                </div>
                <div style={{ fontSize: 14, fontWeight: 650, color: GW.ink, letterSpacing: -0.2 }}>{s.label}</div>
              </div>
              {i < steps.length - 1 && (
                <svg width="22" height="66" viewBox="0 0 22 66" fill="none" style={{ flex: '0 0 auto' }}>
                  <path d="M3 33h13M12 28l5 5-5 5" stroke={i < active ? GW.accent : GW.line} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ transition: 'stroke .4s ease' }}/>
                </svg>
              )}
            </React.Fragment>
          );
        })}
      </div>
    </div>
  );
}

const CARD_W = 296;

// image-dominant reward card (photo placeholder until real assets land)
function RewardCard({ r }) {
  return (
    <div style={{ width: CARD_W, ...rlCard, padding: 20, boxSizing: 'border-box', display: 'flex', flexDirection: 'column', textAlign: 'center' }}>
      <div style={{ width: '100%', aspectRatio: '4 / 3', borderRadius: 16, overflow: 'hidden', marginBottom: 18, position: 'relative',
        background: `radial-gradient(120% 120% at 50% 0%, ${GW.accentSoft}, #eef1f6)`, border: `1px solid ${GW.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <div style={{ width: 64, height: 64, borderRadius: 18, background: '#fff', border: `1px solid ${GW.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 6px 16px -8px rgba(20,22,50,0.2)' }}>
          {rewardIcons[r.key](GW.accentDark, 30)}
        </div>
        <span style={{ position: 'absolute', left: 10, bottom: 9, fontFamily: GW.mono, fontSize: 8.5, letterSpacing: 0.4, color: GW.inkFaint, textTransform: 'uppercase', background: 'rgba(255,255,255,0.7)', padding: '2px 6px', borderRadius: 5 }}>reward photo</span>
      </div>
      <div style={{ fontSize: 17, fontWeight: 650, color: GW.ink, letterSpacing: -0.3, lineHeight: 1.25, minHeight: 42, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{r.name}</div>
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'center', gap: 7, marginTop: 8 }}>
        <span style={{ fontSize: 30, fontWeight: 700, color: GW.accentDark, letterSpacing: -1, lineHeight: 1, fontVariantNumeric: 'tabular-nums' }}>{r.cost}</span>
        <span style={{ fontFamily: GW.mono, fontSize: 11, fontWeight: 500, letterSpacing: 1.5, color: GW.inkFaint }}>PTS</span>
      </div>
      <div style={{ fontSize: 12.5, color: GW.inkFaint, marginTop: 6 }}>{r.classes}</div>
    </div>
  );
}

function NavBtn({ dir, onClick }) {
  return (
    <button onClick={onClick} aria-label={dir < 0 ? 'Previous reward' : 'Next reward'} style={{
      width: 44, height: 44, borderRadius: 999, border: `1px solid ${GW.line}`, background: '#fff', cursor: 'pointer',
      display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 2px 10px rgba(20,22,40,0.08)', flex: '0 0 auto' }}>
      <svg width="17" height="17" viewBox="0 0 16 16" fill="none" stroke={GW.ink} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" style={{ transform: dir < 0 ? 'scaleX(-1)' : 'none' }}><path d="M6 3l5 5-5 5"/></svg>
    </button>
  );
}

// 3-card carousel: centre focused, two peeking sides; auto-advance + nav.
function RewardsCarousel() {
  const REWARDS = COPY.loyalty.rewards;
  const n = REWARDS.length;
  const [active, setActive] = React.useState(0);
  const inView = React.useRef(true);
  const wrap = React.useRef(null);
  const timer = React.useRef(null);
  const restart = () => {
    if (timer.current) clearInterval(timer.current);
    timer.current = setInterval(() => { if (inView.current) setActive((a) => (a + 1) % n); }, 4800);
  };
  React.useEffect(() => {
    const el = wrap.current;
    const io = new IntersectionObserver((e) => { inView.current = e[0].isIntersecting; }, { threshold: 0 });
    if (el) io.observe(el);
    restart();
    return () => { io.disconnect(); if (timer.current) clearInterval(timer.current); };
  }, []);
  const go = (d) => { setActive((a) => (a + d + n) % n); restart(); };

  const slotFor = (i) => { let r = i - active; if (r > n / 2) r -= n; if (r < -n / 2) r += n; return r; };
  const sideOffset = Math.round(CARD_W * 0.62);

  return (
    <div ref={wrap} style={{ marginTop: 64 }}>
      <div style={{ fontFamily: GW.mono, fontSize: 10.5, letterSpacing: 0.6, color: GW.inkFaint, textTransform: 'uppercase', textAlign: 'center', marginBottom: 30 }}>{COPY.loyalty.rewardsLabel}</div>

      <div style={{ position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 22 }}>
        <NavBtn dir={-1} onClick={() => go(-1)} />
        <div style={{ position: 'relative', width: CARD_W + sideOffset * 2, maxWidth: '100%', height: 360 }}>
          {REWARDS.map((r, i) => {
            const slot = slotFor(i);
            const focused = slot === 0;
            return (
              <div key={r.key} style={{ position: 'absolute', top: 0, left: '50%', width: CARD_W,
                transform: `translateX(-50%) translateX(${slot * sideOffset}px) scale(${focused ? 1 : 0.84})`,
                opacity: Math.abs(slot) > 1 ? 0 : focused ? 1 : 0.36, zIndex: focused ? 3 : 1,
                filter: focused ? 'none' : 'saturate(0.85)', transition: 'transform .55s cubic-bezier(.4,.1,.2,1), opacity .55s ease', pointerEvents: focused ? 'auto' : 'none' }}>
                <RewardCard r={r} />
              </div>
            );
          })}
        </div>
        <NavBtn dir={1} onClick={() => go(1)} />
      </div>

      {/* benefit caption for the focused reward */}
      <div style={{ maxWidth: 600, margin: '36px auto 0', textAlign: 'center', position: 'relative', minHeight: 60 }}>
        {REWARDS.map((r, i) => (
          <p key={r.key} style={{ position: i === active ? 'relative' : 'absolute', inset: i === active ? 'auto' : 0, margin: 0,
            fontSize: 'clamp(15px,1.7vw,17px)', lineHeight: 1.55, fontWeight: 450, color: GW.inkSoft, textWrap: 'pretty',
            opacity: i === active ? 1 : 0, transition: 'opacity .5s ease', pointerEvents: 'none' }}>{r.benefit}</p>
        ))}
      </div>

      {/* dots */}
      <div style={{ display: 'flex', gap: 7, justifyContent: 'center', marginTop: 22 }}>
        {REWARDS.map((_, i) => (
          <button key={i} onClick={() => { setActive(i); restart(); }} aria-label={`Reward ${i + 1}`} style={{ width: i === active ? 20 : 7, height: 7, borderRadius: 999, border: 'none', cursor: 'pointer', padding: 0, background: i === active ? GW.accent : GW.line, transition: 'all .4s ease' }}></button>
        ))}
      </div>
    </div>
  );
}

function LoyaltySection() {
  return (
    <section data-screen-label="06 Loyalty" style={{ width: '100%', background: GW.bg, fontFamily: GW.sans, position: 'relative', overflow: 'hidden' }}>
      <GWGlow style={{ top: 120, left: '50%', transform: 'translateX(-50%)', width: 820, height: 540, background: `radial-gradient(50% 50% at 50% 50%, ${GW.accentGlow}, transparent 72%)` }} />
      <div style={{ position: 'relative', zIndex: 1, maxWidth: GW.maxW, margin: '0 auto', padding: '100px 32px 108px' }}>
        <div style={{ textAlign: 'center', maxWidth: 900, margin: '0 auto' }}>
          <h2 style={{ margin: 0, fontSize: 'clamp(32px,3.6vw,48px)', lineHeight: 1.05, letterSpacing: -1.8, fontWeight: 600, color: GW.ink, textWrap: 'balance' }}>{COPY.loyalty.heading}</h2>
          <p style={{ margin: '18px auto 0', maxWidth: 1040, fontSize: 'clamp(17px,1.9vw,20px)', lineHeight: 1.5, fontWeight: 450, color: GW.inkSoft, textWrap: 'pretty' }}>{COPY.loyalty.blurb}</p>
        </div>

        <div style={{ marginTop: 64 }}>
          <PointsLoop />
        </div>

        <RewardsCarousel />
      </div>
    </section>
  );
}

window.LoyaltySection = LoyaltySection;
