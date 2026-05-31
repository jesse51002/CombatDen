// feed.jsx — §4 "Agentic video feed": one big feature cell (real phone screen
// cropped) + a row of 3 compact cells (02/03/04) with real class thumbnails.
// Self-contained (the handoff's FeedFinal never used the separate Visual* mocks;
// it only read the FEED data, now COPY.feed). Copy from COPY.feed.
// Exports FeedFinal.

const FF_GREEN = '#1F8A5B';
const FF_RED = '#D0584F';
const FF_PILS = ['assets/landing/pil-1.jpeg', 'assets/landing/pil-2.jpeg', 'assets/landing/pil-3.jpeg', 'assets/landing/pil-4.jpeg'];
const FF_SCREEN = 'assets/landing/screen-full.png';

// Raycast-style soft card: gentle gradient, low-contrast hairline border,
// soft layered shadow, faint top highlight — never flat harsh white.
const ffCard = {
  background: 'linear-gradient(180deg, #ffffff, #f5f7fb)',
  border: '1px solid rgba(20,22,40,0.065)',
  borderRadius: 22,
  boxShadow: '0 1px 2px rgba(20,22,40,0.03), 0 22px 50px -30px rgba(20,22,50,0.2), inset 0 1px 0 rgba(255,255,255,0.9)',
};
const FF_FADE = '#f5f7fb';

// real video thumbnail (image-backed)
function RThumb({ src, w = '100%', h = 78, r = 12, mark, badge, faded = false, play = true, objPos = 'center', rotate = 0, ring, shadow, style = {} }) {
  const mc = mark === 'check' ? FF_GREEN : FF_RED;
  return (
    <div style={{ width: w, height: h, position: 'relative', flex: '0 0 auto', transform: rotate ? `rotate(${rotate}deg)` : undefined, ...style }}>
      <div style={{ position: 'absolute', inset: 0, borderRadius: r, overflow: 'hidden', boxShadow: shadow, outline: ring ? `2.5px solid ${ring}` : 'none', outlineOffset: ring ? 1 : 0, background: '#d8dbe0' }}>
        <img src={src} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover', objectPosition: objPos, display: 'block', filter: faded ? 'grayscale(0.85) brightness(1.02)' : 'none', opacity: faded ? 0.55 : 1 }} />
        {faded && <div style={{ position: 'absolute', inset: 0, background: 'rgba(243,245,248,0.35)' }}></div>}
        {play && !faded && (
          <div style={{ position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%,-50%)', width: 26, height: 26, borderRadius: 999, background: 'rgba(255,255,255,0.9)', display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 2px 6px rgba(0,0,0,0.2)' }}>
            <svg width="9" height="10" viewBox="0 0 18 20" fill={GW.accent}><path d="M2 2.5v15a1 1 0 001.5.87l13-7.5a1 1 0 000-1.74l-13-7.5A1 1 0 002 2.5z"/></svg>
          </div>
        )}
      </div>
      {mark && (
        <div style={{ position: 'absolute', top: -8, right: -8, width: 24, height: 24, borderRadius: 999, background: mc, display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: `0 3px 9px ${mc}66`, border: '2.5px solid #fff' }}>
          {mark === 'check'
            ? <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="#fff" strokeWidth="2.3" strokeLinecap="round" strokeLinejoin="round"><path d="M2.5 6.2l2.2 2.2L9.5 3.6"/></svg>
            : <svg width="11" height="11" viewBox="0 0 12 12" fill="none" stroke="#fff" strokeWidth="2.3" strokeLinecap="round"><path d="M3 3l6 6M9 3l-6 6"/></svg>}
        </div>
      )}
      {badge && (
        <div style={{ position: 'absolute', top: -8, right: -8, width: 24, height: 24, borderRadius: 999, background: GW.accent, display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: `0 3px 9px ${GW.accent}66`, border: '2.5px solid #fff' }}>
          <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="#fff" strokeWidth="2.4" strokeLinecap="round"><path d="M6 2v8M2 6h8"/></svg>
        </div>
      )}
    </div>
  );
}

// real phone: full app screenshot, vertically cropped to top portion
function RealPhone({ width = 280, visible = 0.6 }) {
  const fullH = Math.round(width * 2.226);     // screenshot is 1344×2992
  return (
    <div style={{ width, height: Math.round(fullH * visible), overflow: 'hidden', position: 'relative' }}>
      <div style={{ width, height: fullH, borderRadius: 44, background: 'linear-gradient(150deg, #fafbfc, #e7e9ee)', padding: 10,
        boxShadow: '0 2px 4px rgba(20,22,30,0.14), 0 40px 70px -30px rgba(20,22,40,0.32), inset 0 0 0 1px rgba(255,255,255,0.7)' }}>
        <div style={{ height: '100%', borderRadius: 36, overflow: 'hidden', background: '#000', boxShadow: 'inset 0 0 0 2px rgba(0,0,0,0.85)' }}>
          <img src={FF_SCREEN} alt="App video feed" style={{ width: '100%', display: 'block' }} />
        </div>
      </div>
    </div>
  );
}

// blinking text caret — signals the text is live user input
function Caret() {
  return <span style={{ display: 'inline-block', width: 2, height: '1.05em', background: GW.accent, marginLeft: 2, borderRadius: 1, verticalAlign: '-0.14em', animation: 'ffBlink 1.05s step-end infinite' }}></span>;
}

// agent prompt bubble (owner typing to the agent)
function FFBubble({ children, accent = false, size = 13 }) {
  return (
    <div style={{ display: 'inline-flex', alignItems: 'center', gap: 9, background: accent ? GW.accentSoft : GW.surface, border: `1px solid ${accent ? GW.accent + '33' : GW.line}`, borderRadius: '14px 14px 14px 4px', padding: '9px 14px', boxShadow: '0 2px 10px rgba(20,22,40,0.06)', maxWidth: '100%' }}>
      <span style={{ width: 18, height: 18, borderRadius: 6, background: `linear-gradient(150deg, ${GW.accent}, ${GW.accentDark})`, flex: '0 0 auto', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <svg width="10" height="10" viewBox="0 0 16 16" fill="#fff"><path d="M8 1l1.6 4.4L14 7l-4.4 1.6L8 13l-1.6-4.4L2 7l4.4-1.6z"/></svg>
      </span>
      <span style={{ fontSize: size, fontWeight: 500, color: GW.ink, lineHeight: 1.35 }}>{children}</span>
    </div>
  );
}

// caption: bold statement
function FFCap({ children, size = 17, max }) {
  return (
    <p style={{ margin: 0, fontSize: size, fontWeight: 600, lineHeight: 1.25, letterSpacing: -0.4, color: GW.ink, maxWidth: max, textWrap: 'balance' }}>{children}</p>
  );
}

// column card (Raycast-style soft surface)
function FeedCell({ children }) {
  return (
    <div style={{ ...ffCard, padding: 22, display: 'flex', flexDirection: 'column', height: '100%' }}>
      {children}
    </div>
  );
}

function FeedFinal() {
  const items = COPY.feed.items;
  return (
    <section data-screen-label="04 Video feed" style={{ width: '100%', background: GW.bg, fontFamily: GW.sans }}>
      <style>{`@keyframes ffBlink{0%,50%{opacity:1}50.01%,100%{opacity:0}}`}</style>
      <div style={{ maxWidth: GW.maxW, margin: '0 auto', padding: '88px 32px 96px' }}>
        <div style={{ textAlign: 'center', maxWidth: 760, margin: '0 auto' }}>
          <h2 style={{ margin: 0, fontSize: 'clamp(30px,3.4vw,44px)', lineHeight: 1.08, letterSpacing: -1.5, fontWeight: 600, color: GW.ink, textWrap: 'balance' }}>{COPY.feed.heading}</h2>
        </div>

        {/* 01 — create; Raycast-style soft card */}
        <div style={{ ...ffCard, marginTop: 56, borderRadius: 28, overflow: 'hidden', display: 'grid', gridTemplateColumns: '1fr 1fr', alignItems: 'stretch' }}>
          <div style={{ padding: '40px 28px 44px 44px', display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
            <FFCap size={24} max={500}>{items[0].text}</FFCap>
            <p style={{ margin: '16px 0 0', fontSize: 16.5, lineHeight: 1.5, fontWeight: 450, color: GW.inkSoft, maxWidth: 420, textWrap: 'pretty' }}>{COPY.feed.lead}</p>
          </div>
          {/* phone: prompt bubble + arrow pointing into the phone, screen bleeds off bottom */}
          <div style={{ position: 'relative', display: 'flex', flexDirection: 'column', alignItems: 'center', paddingTop: 26, overflow: 'hidden' }}>
            <GWDotGrid color="rgba(20,22,40,0.05)" fade="radial-gradient(90% 90% at 50% 30%, #000 40%, transparent 80%)" />
            <div style={{ position: 'relative', zIndex: 3 }}><FFBubble accent size={14}>Video feed for a yoga gym<Caret /></FFBubble></div>
            <svg width="58" height="42" viewBox="0 0 58 42" fill="none" style={{ position: 'relative', zIndex: 3, marginTop: 3, marginBottom: 1 }}>
              <path d="M30 3 C 20 13, 40 21, 29 35" stroke={GW.accent} strokeWidth="2.4" strokeLinecap="round" />
              <path d="M29 36 l -8 -6 M29 36 l 8 -7" stroke={GW.accent} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
            <div style={{ position: 'relative', zIndex: 1, marginTop: 2 }}><RealPhone width={290} visible={0.6} /></div>
            {/* gentle fade at the vertical crop */}
            <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 70, background: `linear-gradient(to top, ${FF_FADE}, transparent)`, zIndex: 2, pointerEvents: 'none' }}></div>
          </div>
        </div>

        {/* ROW of 3 — 02 / 03 / 04 soft cards */}
        <div style={{ marginTop: 24, display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 24 }}>

          {/* 02 — tell what you want / don't */}
          <FeedCell>
            <FFCap>{items[1].text}</FFCap>
            <div style={{ marginTop: 18, marginBottom: 16 }}><FFBubble>More slow flow, less loud HIIT<Caret /></FFBubble></div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, flex: 1, gridAutoRows: 'minmax(92px, 1fr)' }}>
              <RThumb src={FF_PILS[0]} h="100%" mark="check" objPos="center 30%" />
              <RThumb src={FF_PILS[2]} h="100%" mark="x" faded play={false} />
              <RThumb src={FF_PILS[1]} h="100%" mark="x" faded play={false} />
              <RThumb src={FF_PILS[3]} h="100%" mark="check" />
            </div>
          </FeedCell>

          {/* 03 — add your own, prioritized */}
          <FeedCell>
            <FFCap>{items[2].text}</FFCap>
            <div style={{ marginTop: 20, display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, flex: 1, gridAutoRows: 'minmax(92px, 1fr)' }}>
              <RThumb src={FF_PILS[3]} h="100%" r={13} badge ring={GW.accent} />
              <RThumb src={FF_PILS[0]} h="100%" r={13} badge objPos="center 25%" />
              <RThumb src={FF_PILS[1]} h="100%" r={13} badge />
              <RThumb src={FF_PILS[2]} h="100%" r={13} badge />
            </div>
          </FeedCell>

          {/* 04 — remove once, keeps similar out */}
          <FeedCell>
            <FFCap>{items[3].text}</FFCap>
            <div style={{ marginTop: 20, display: 'flex', flexDirection: 'column', gap: 14, flex: 1 }}>
              <div style={{ position: 'relative', width: '100%', flex: 1, minHeight: 92 }}>
                <RThumb src={FF_PILS[1]} h="100%" r={13} faded play={false} />
                <div style={{ position: 'absolute', right: -6, top: -12, background: GW.surface, border: `1px solid ${GW.line}`, borderRadius: '12px 12px 12px 3px', padding: '6px 11px', boxShadow: '0 6px 16px rgba(20,22,40,0.16)', display: 'flex', alignItems: 'center', gap: 7 }}>
                  <span style={{ width: 17, height: 17, borderRadius: 999, background: FF_RED, display: 'flex', alignItems: 'center', justifyContent: 'center', flex: '0 0 auto' }}>
                    <svg width="9" height="9" viewBox="0 0 12 12" fill="none" stroke="#fff" strokeWidth="2.3" strokeLinecap="round"><path d="M3 3l6 6M9 3l-6 6"/></svg>
                  </span>
                  <span style={{ fontSize: 12, fontWeight: 600, color: GW.ink, whiteSpace: 'nowrap' }}>Not this one<Caret /></span>
                </div>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
                <svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke={GW.accent} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"><path d="M8 1.5l5.5 2v4c0 3.4-2.4 5.7-5.5 6.9C4.9 13.2 2.5 10.9 2.5 7.5v-4z"/></svg>
                <span style={{ fontFamily: GW.mono, fontSize: 9.5, color: GW.inkSoft, letterSpacing: 0.3, textTransform: 'uppercase' }}>Agent cuts similar</span>
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 10 }}>
                {[FF_PILS[0], FF_PILS[2], FF_PILS[3]].map((s, i) => (
                  <RThumb key={i} src={s} h={52} r={9} faded play={false} mark="x" />
                ))}
              </div>
            </div>
          </FeedCell>
        </div>
      </div>
    </section>
  );
}

window.FeedFinal = FeedFinal;
