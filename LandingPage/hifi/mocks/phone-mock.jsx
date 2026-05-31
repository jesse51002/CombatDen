// phone-mock.jsx — straight-on / tilted phone mockup for the hero.
// THEME-DRIVEN: GymAppScreen reads the global active theme (theme-store.jsx) and
// re-skins on every theme change — the hero video tile swaps to the theme's
// image and every accent re-tints. Ported from the handoff phone-mock.jsx.
// Exports PhoneMock to window.

const phoneBase = {
  ink: '#1b1d22',
  inkSoft: '#5b606b',
  line: 'rgba(20,22,28,0.08)',
  surface: '#ffffff',
  surfaceAlt: '#f4f5f8',
  mono: '"Geist Mono", ui-monospace, "SF Mono", Menlo, monospace',
  sans: '"Geist", "Inter", system-ui, -apple-system, sans-serif',
};

// Striped media placeholder with a centered mono caption (fallback / thumbs).
function MediaSlot({ label, height, radius = 0, style = {} }) {
  return (
    <div style={{
      height, borderRadius: radius, position: 'relative', overflow: 'hidden',
      background: 'repeating-linear-gradient(135deg, #e9ebf0 0 11px, #eff1f5 11px 22px)',
      display: 'flex', alignItems: 'center', justifyContent: 'center', ...style,
    }}>
      {label && <span style={{
        fontFamily: phoneBase.mono, fontSize: 9.5, letterSpacing: 0.6,
        textTransform: 'uppercase', color: 'rgba(40,44,54,0.42)',
        background: 'rgba(255,255,255,0.7)', padding: '3px 7px', borderRadius: 4,
      }}>{label}</span>}
    </div>
  );
}

// The app screen, re-skinned by the global active theme.
function GymAppScreen() {
  const { theme, asset } = useTheme();
  const accent = theme.accent;
  const accentSoft = gwRgba(accent, 0.12);
  const t = phoneBase;
  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', background: t.surface, fontFamily: t.sans }}>
      {/* status bar */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '11px 22px 4px', fontSize: 12, fontWeight: 600, color: t.ink }}>
        <span style={{ fontVariantNumeric: 'tabular-nums' }}>9:41</span>
        <div style={{ display: 'flex', gap: 5, alignItems: 'center' }}>
          <svg width="16" height="11" viewBox="0 0 16 11" fill={t.ink}><rect x="0" y="7" width="3" height="4" rx="1"/><rect x="4.3" y="5" width="3" height="6" rx="1"/><rect x="8.6" y="2.5" width="3" height="8.5" rx="1"/><rect x="12.9" y="0" width="3" height="11" rx="1"/></svg>
          <svg width="22" height="11" viewBox="0 0 22 11" fill="none"><rect x="0.5" y="0.5" width="18" height="10" rx="2.5" stroke={t.ink} opacity="0.4"/><rect x="2" y="2" width="14" height="7" rx="1.3" fill={t.ink}/><rect x="19.5" y="3.5" width="1.6" height="4" rx="0.8" fill={t.ink} opacity="0.4"/></svg>
        </div>
      </div>

      {/* header: gym mark + greeting + bell */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 18px 12px' }}>
        <div style={{ width: 34, height: 34, borderRadius: 10, background: accentSoft, border: `1px solid ${t.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', flex: '0 0 auto' }}>
          <span style={{ fontFamily: t.mono, fontSize: 8, color: accent, letterSpacing: 0.3 }}>LOGO</span>
        </div>
        <div style={{ minWidth: 0, flex: 1 }}>
          <div style={{ fontSize: 9, fontFamily: t.mono, letterSpacing: 0.5, color: t.inkSoft, textTransform: 'uppercase', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{theme.name}</div>
          <div style={{ fontSize: 14, fontWeight: 650, color: t.ink, letterSpacing: -0.2 }}>Good evening, Mara</div>
        </div>
        <div style={{ width: 32, height: 32, borderRadius: 999, background: t.surfaceAlt, display: 'flex', alignItems: 'center', justifyContent: 'center', flex: '0 0 auto' }}>
          <svg width="15" height="15" viewBox="0 0 16 16" fill="none" stroke={t.ink} strokeWidth="1.4" strokeLinecap="round"><path d="M4 7a4 4 0 018 0c0 3 1.2 4 1.2 4H2.8S4 10 4 7z"/><path d="M6.5 13.5a1.6 1.6 0 003 0"/></svg>
        </div>
      </div>

      {/* hero video feed card — theme image (or striped fallback) */}
      <div style={{ padding: '0 16px', flex: 1, minHeight: 0 }}>
        <div style={{ position: 'relative', height: '100%', borderRadius: 20, overflow: 'hidden', border: `1px solid ${t.line}`, boxShadow: '0 6px 20px rgba(20,22,30,0.08)' }}>
          {asset
            ? <img src={asset} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
            : <MediaSlot label="video feed" height="100%" />}
          {/* brand tint over the media */}
          <div style={{ position: 'absolute', inset: 0, background: `linear-gradient(160deg, ${gwRgba(accent, 0.16)}, transparent 60%)`, pointerEvents: 'none' }}></div>
          {/* play button */}
          <div style={{ position: 'absolute', top: '42%', left: '50%', transform: 'translate(-50%,-50%)', width: 52, height: 52, borderRadius: 999, background: 'rgba(255,255,255,0.92)', boxShadow: '0 8px 24px rgba(0,0,0,0.18)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <svg width="18" height="20" viewBox="0 0 18 20" fill={accent}><path d="M2 2.5v15a1 1 0 001.5.87l13-7.5a1 1 0 000-1.74l-13-7.5A1 1 0 002 2.5z"/></svg>
          </div>
          {/* top chip */}
          <div style={{ position: 'absolute', top: 12, left: 12, display: 'flex', gap: 6, alignItems: 'center', background: 'rgba(20,22,28,0.62)', backdropFilter: 'blur(6px)', padding: '5px 9px', borderRadius: 999 }}>
            <span style={{ width: 6, height: 6, borderRadius: 999, background: accent }}></span>
            <span style={{ fontFamily: t.mono, fontSize: 8.5, letterSpacing: 0.5, color: '#fff', textTransform: 'uppercase' }}>For you</span>
          </div>
          {/* bottom caption */}
          <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, padding: '34px 14px 14px', background: 'linear-gradient(to top, rgba(15,16,20,0.78), rgba(15,16,20,0))' }}>
            <div style={{ fontSize: 14.5, fontWeight: 650, color: '#fff', letterSpacing: -0.2, lineHeight: 1.2 }}>Tonight: 20-min Conditioning</div>
            <div style={{ fontSize: 11, color: 'rgba(255,255,255,0.78)', marginTop: 3 }}>Picked for you · 3 days since your last class</div>
          </div>
        </div>
      </div>

      {/* up next row */}
      <div style={{ display: 'flex', gap: 10, padding: '12px 16px 6px' }}>
        {['mobility', 'strength'].map((l) => (
          <div key={l} style={{ flex: 1, display: 'flex', gap: 8, alignItems: 'center', background: t.surfaceAlt, borderRadius: 12, padding: 7 }}>
            <MediaSlot label="" height={34} radius={8} style={{ width: 44, flex: '0 0 auto' }} />
            <div style={{ minWidth: 0 }}>
              <div style={{ fontSize: 10.5, fontWeight: 600, color: t.ink, textTransform: 'capitalize' }}>{l}</div>
              <div style={{ fontSize: 9, color: t.inkSoft }}>Up next</div>
            </div>
          </div>
        ))}
      </div>

      {/* bottom tab bar */}
      <div style={{ display: 'flex', justifyContent: 'space-around', alignItems: 'center', padding: '10px 22px 16px', borderTop: `1px solid ${t.line}` }}>
        {[
          { d: 'M2 8.5L9 3l7 5.5V15a1 1 0 01-1 1H3a1 1 0 01-1-1z', on: true },
          { d: 'M3 4.5h12M3 9h12M3 13.5h8', on: false },
          { d: 'M9 2a4 4 0 100 8 4 4 0 000-8zM2.5 16a6.5 6.5 0 0113 0', on: false },
        ].map((ic, i) => (
          <svg key={i} width="19" height="19" viewBox="0 0 18 18" fill="none" stroke={ic.on ? accent : 'rgba(20,22,28,0.32)'} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"><path d={ic.d}/></svg>
        ))}
      </div>
    </div>
  );
}

// PhoneMock — the device frame around GymAppScreen. The glow tints to the
// active theme so a theme change re-skins the whole device, not just the screen.
function PhoneMock({ width = 300, tilt = 'none', glow = true, style = {} }) {
  const { theme } = useTheme();
  const height = Math.round(width * 2.04);
  const transforms = {
    none: 'none',
    left: 'perspective(2100px) rotateY(16deg) rotateX(3deg) rotateZ(0.5deg)',
    right: 'perspective(2100px) rotateY(-16deg) rotateX(3deg) rotateZ(-0.5deg)',
  };
  const isTilt = tilt !== 'none';
  return (
    <div style={{ position: 'relative', width, height, ...style }}>
      {glow && (
        <div style={{ position: 'absolute', inset: '-18% -22%', background: `radial-gradient(50% 46% at 50% 46%, ${gwRgba(theme.accent, 0.34)}, transparent 72%)`, filter: 'blur(8px)', zIndex: 0, pointerEvents: 'none', transition: 'background .3s ease' }}></div>
      )}
      <div style={{
        position: 'relative', zIndex: 1, width, height, borderRadius: 46,
        background: 'linear-gradient(150deg, #fafbfc, #e7e9ee)',
        padding: 11,
        boxShadow: isTilt
          ? '0 2px 4px rgba(20,22,30,0.18), 42px 60px 90px -30px rgba(20,22,40,0.42), inset 0 0 0 1px rgba(255,255,255,0.7)'
          : '0 2px 4px rgba(20,22,30,0.14), 0 44px 80px -28px rgba(20,22,40,0.36), inset 0 0 0 1px rgba(255,255,255,0.7)',
        transform: transforms[tilt],
        transformStyle: 'preserve-3d',
      }}>
        {/* inner bezel */}
        <div style={{ position: 'relative', height: '100%', borderRadius: 36, overflow: 'hidden', background: '#000', boxShadow: 'inset 0 0 0 2px rgba(0,0,0,0.85)' }}>
          {/* dynamic island */}
          <div style={{ position: 'absolute', top: 9, left: '50%', transform: 'translateX(-50%)', width: 86, height: 24, borderRadius: 999, background: '#0a0a0c', zIndex: 5 }}></div>
          <div style={{ height: '100%', borderRadius: 34, overflow: 'hidden' }}>
            <GymAppScreen />
          </div>
        </div>
      </div>
    </div>
  );
}

window.PhoneMock = PhoneMock;
