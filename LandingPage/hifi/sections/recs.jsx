// recs.jsx — §5 "Perfectly timed content": a phone auto-loops a booking flow,
// then the matched video pops up at the right moment. Largely visual; copy is
// just header + subheader (COPY.recs). Exports RecsSection.
// (The handoff defined a TimelineRail but never rendered it — omitted here.)

const REC_GREEN = '#1F8A5B';

// device shell (bezel only; takes children as the screen)
function PhoneShell({ width = 296, children }) {
  const height = Math.round(width * 2.04);
  return (
    <div style={{ position: 'relative', width, height }}>
      <div style={{ width, height, borderRadius: 46, background: 'linear-gradient(150deg, #fafbfc, #e7e9ee)', padding: 11,
        boxShadow: '0 2px 4px rgba(20,22,30,0.14), 0 44px 80px -28px rgba(20,22,40,0.4), inset 0 0 0 1px rgba(255,255,255,0.7)' }}>
        <div style={{ position: 'relative', height: '100%', borderRadius: 36, overflow: 'hidden', background: '#fff', boxShadow: 'inset 0 0 0 2px rgba(0,0,0,0.85)' }}>
          <div style={{ position: 'absolute', top: 9, left: '50%', transform: 'translateX(-50%)', width: 86, height: 24, borderRadius: 999, background: '#0a0a0c', zIndex: 20 }}></div>
          <div style={{ height: '100%', borderRadius: 34, overflow: 'hidden' }}>{children}</div>
        </div>
      </div>
    </div>
  );
}

function RecStatusBar() {
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '11px 22px 4px', fontSize: 12, fontWeight: 600, color: '#16181d' }}>
      <span style={{ fontVariantNumeric: 'tabular-nums' }}>9:41</span>
      <div style={{ display: 'flex', gap: 5, alignItems: 'center' }}>
        <svg width="16" height="11" viewBox="0 0 16 11" fill="#16181d"><rect x="0" y="7" width="3" height="4" rx="1"/><rect x="4.3" y="5" width="3" height="6" rx="1"/><rect x="8.6" y="2.5" width="3" height="8.5" rx="1"/><rect x="12.9" y="0" width="3" height="11" rx="1"/></svg>
        <svg width="22" height="11" viewBox="0 0 22 11" fill="none"><rect x="0.5" y="0.5" width="18" height="10" rx="2.5" stroke="#16181d" opacity="0.4"/><rect x="2" y="2" width="14" height="7" rx="1.3" fill="#16181d"/></svg>
      </div>
    </div>
  );
}

// the booking screen (always present underneath)
function BookingScreen({ phase }) {
  const classes = [
    { name: 'Vinyasa Flow', when: 'Tomorrow · 6:00 PM', img: 'assets/landing/pil-2.jpeg' },
    { name: 'Reformer Strength', when: 'Wed · 7:30 AM', img: 'assets/landing/pil-3.jpeg' },
    { name: 'Slow Flow & Restore', when: 'Thu · 8:00 PM', img: 'assets/landing/pil-4.jpeg' },
    { name: 'Mobility Reset', when: 'Fri · 9:00 AM', img: 'assets/landing/pil-1.jpeg' },
  ];
  const booked = phase >= 1;
  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', background: '#fff', fontFamily: GW.sans }}>
      <RecStatusBar />
      <div style={{ padding: '10px 18px 6px' }}>
        <div style={{ fontFamily: GW.mono, fontSize: 9.5, letterSpacing: 0.5, color: GW.inkFaint, textTransform: 'uppercase' }}>Book a class</div>
        <div style={{ fontSize: 19, fontWeight: 650, color: GW.ink, letterSpacing: -0.4, marginTop: 2 }}>This week</div>
      </div>
      <div style={{ padding: '6px 14px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {classes.map((c, i) => {
          const active = i === 0;
          return (
            <div key={c.name} style={{ position: 'relative', display: 'flex', alignItems: 'center', gap: 11, padding: 9, borderRadius: 15,
              background: active ? GW.accentSoft : GW.bgAlt, border: `1px solid ${active ? GW.accent + '33' : 'transparent'}`,
              transition: 'all .4s ease' }}>
              <div style={{ width: 52, height: 52, borderRadius: 11, overflow: 'hidden', flex: '0 0 auto', background: '#d8dbe0' }}>
                <img src={c.img} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
              </div>
              <div style={{ minWidth: 0, flex: 1 }}>
                <div style={{ fontSize: 13.5, fontWeight: 650, color: GW.ink, letterSpacing: -0.2 }}>{c.name}</div>
                <div style={{ fontSize: 11, color: GW.inkSoft, marginTop: 2 }}>{c.when}</div>
              </div>
              {active ? (
                <div style={{ position: 'relative', flex: '0 0 auto' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 5, fontSize: 12, fontWeight: 650, color: '#fff',
                    padding: '7px 13px', borderRadius: 999, background: booked ? REC_GREEN : `linear-gradient(180deg, ${GW.accent}, ${GW.accentDark})`,
                    boxShadow: booked ? `0 4px 12px ${REC_GREEN}55` : `0 4px 12px ${GW.accent}55`, transition: 'all .4s ease', whiteSpace: 'nowrap' }}>
                    {booked
                      ? (<><svg width="11" height="11" viewBox="0 0 12 12" fill="none" stroke="#fff" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M2.5 6.2l2.2 2.2L9.5 3.6"/></svg>Booked</>)
                      : 'Book'}
                  </div>
                </div>
              ) : (
                <div style={{ fontSize: 12, fontWeight: 600, color: GW.inkFaint, padding: '7px 13px', flex: '0 0 auto' }}>Book</div>
              )}
            </div>
          );
        })}
      </div>

      {/* tap ripple on the Book button near end of phase 0 */}
      {phase === 0 && (
        <div style={{ position: 'absolute', top: 150, right: 34, width: 30, height: 30, borderRadius: 999, border: `2px solid ${GW.accent}`, animation: 'recTap 1.6s ease-out infinite', pointerEvents: 'none' }}></div>
      )}

      {/* bottom tab bar */}
      <div style={{ marginTop: 'auto', display: 'flex', justifyContent: 'space-around', alignItems: 'center', padding: '12px 24px 18px', borderTop: `1px solid ${GW.lineSoft}` }}>
        {[
          { d: 'M2 8.5L9 3l7 5.5V15a1 1 0 01-1 1H3a1 1 0 01-1-1z', on: false },
          { d: 'M3 4.5h12M3 9h12M3 13.5h8', on: true },
          { d: 'M9 2.5l1.9 4 4.3.5-3.2 2.9.9 4.2L9 12l-3.8 2 .9-4.2L2.9 7l4.3-.5z', on: false },
          { d: 'M3 4.5h12v9H3zM3 8h12', on: false },
        ].map((ic, i) => (
          <svg key={i} width="20" height="20" viewBox="0 0 18 18" fill="none" stroke={ic.on ? GW.accent : 'rgba(20,22,28,0.3)'} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"><path d={ic.d}/></svg>
        ))}
      </div>
    </div>
  );
}

// the matched-video notification that pops up (phase 3)
function VideoPop({ show }) {
  return (
    <div style={{ position: 'absolute', left: 12, right: 12, top: 14, zIndex: 15,
      transform: show ? 'translateY(0) scale(1)' : 'translateY(-130%) scale(0.96)',
      opacity: show ? 1 : 0, transition: 'transform .6s cubic-bezier(.2,.9,.3,1.2), opacity .4s ease' }}>
      <div style={{ background: 'rgba(255,255,255,0.86)', backdropFilter: 'saturate(180%) blur(18px)', WebkitBackdropFilter: 'saturate(180%) blur(18px)',
        border: `1px solid ${GW.line}`, borderRadius: 20, padding: 11, boxShadow: '0 18px 44px -16px rgba(20,22,50,0.4)', display: 'flex', gap: 11, alignItems: 'center' }}>
        <div style={{ position: 'relative', width: 78, height: 60, borderRadius: 13, overflow: 'hidden', flex: '0 0 auto', background: '#d8dbe0' }}>
          <img src="assets/landing/pil-1.jpeg" alt="" style={{ width: '100%', height: '100%', objectFit: 'cover', objectPosition: 'center 30%' }} />
          <div style={{ position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%,-50%)', width: 24, height: 24, borderRadius: 999, background: 'rgba(255,255,255,0.92)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <svg width="9" height="10" viewBox="0 0 18 20" fill={GW.accent}><path d="M2 2.5v15a1 1 0 001.5.87l13-7.5a1 1 0 000-1.74l-13-7.5A1 1 0 002 2.5z"/></svg>
          </div>
        </div>
        <div style={{ minWidth: 0, flex: 1 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 3 }}>
            <span style={{ width: 16, height: 16, borderRadius: 5, background: `linear-gradient(150deg, ${GW.accent}, ${GW.accentDark})`, display: 'flex', alignItems: 'center', justifyContent: 'center', flex: '0 0 auto' }}>
              <svg width="9" height="9" viewBox="0 0 16 16" fill="#fff"><path d="M8 1l1.6 4.4L14 7l-4.4 1.6L8 13l-1.6-4.4L2 7l4.4-1.6z"/></svg>
            </span>
            <span style={{ fontFamily: GW.mono, fontSize: 8.5, letterSpacing: 0.4, color: GW.inkFaint, textTransform: 'uppercase' }}>30 min before class</span>
          </div>
          <div style={{ fontSize: 13, fontWeight: 650, color: GW.ink, letterSpacing: -0.2, lineHeight: 1.2 }}>Warm up for Vinyasa Flow</div>
          <div style={{ fontSize: 10.5, color: GW.inkSoft, marginTop: 2 }}>5 min · picked for you</div>
        </div>
      </div>
    </div>
  );
}

function RecsSection() {
  const [phase, setPhase] = React.useState(0);
  React.useEffect(() => {
    const seq = [2400, 1500, 1900, 3400]; // phase 0→1→2→3 then loop
    let idx = 0, timer;
    const tick = () => {
      timer = setTimeout(() => { idx = (idx + 1) % 4; setPhase(idx); tick(); }, seq[idx]);
    };
    tick();
    return () => clearTimeout(timer);
  }, []);

  return (
    <section data-screen-label="05 Perfectly timed" style={{ width: '100%', background: GW.bg, fontFamily: GW.sans, overflow: 'hidden' }}>
      <style>{`
        @keyframes recTap { 0%{transform:scale(.6);opacity:.9} 70%{transform:scale(1.5);opacity:0} 100%{opacity:0} }
      `}</style>
      <div style={{ maxWidth: GW.maxW, margin: '0 auto', padding: '96px 32px 104px' }}>
        <div style={{ position: 'relative', display: 'flex', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'center', gap: 'clamp(36px,5vw,80px)' }}>
          <GWGlow style={{ top: '50%', left: '50%', transform: 'translate(-50%,-50%)', width: 820, height: 560, background: `radial-gradient(50% 50% at 50% 50%, ${GW.accentGlow}, transparent 70%)` }} />
          <GWDotGrid color="rgba(20,22,40,0.05)" fade="radial-gradient(80% 80% at 50% 50%, #000 30%, transparent 80%)" />

          {/* copy column */}
          <div style={{ position: 'relative', zIndex: 1, flex: '1 1 340px', maxWidth: 480, minWidth: 280 }}>
            <h2 style={{ margin: 0, fontSize: 'clamp(30px,3.4vw,44px)', lineHeight: 1.08, letterSpacing: -1.5, fontWeight: 600, color: GW.ink, textWrap: 'balance' }}>{COPY.recs.header}</h2>
            <p style={{ margin: '16px 0 0', fontSize: 'clamp(16px,1.8vw,20px)', lineHeight: 1.5, fontWeight: 450, color: GW.inkSoft, textWrap: 'pretty' }}>{COPY.recs.subheader}</p>
          </div>

          {/* phone column */}
          <div style={{ position: 'relative', zIndex: 1, flex: '0 0 auto' }}>
            <PhoneShell width={296}>
              <div style={{ position: 'relative', height: '100%' }}>
                <BookingScreen phase={phase} />
                <VideoPop show={phase === 3} />
              </div>
            </PhoneShell>
          </div>
        </div>
      </div>
    </section>
  );
}

window.RecsSection = RecsSection;
