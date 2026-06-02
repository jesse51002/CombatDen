// theme-preview.jsx — a flat app-screen "screenshot" card in a given brand
// theme. PROP-DRIVEN on purpose: the §3 rail shows many themes side by side,
// so each card takes its own `theme` (it must NOT collapse to the global active
// theme). Ported from the handoff themes-data.jsx. Exports ThemePreview.

function ThemePreview({ theme, width = 184, showName = true, onClick, active = false, style = {} }) {
  const t = theme;
  const h = Math.round(width * 2.02);
  const surface = t.dark ? '#17171d' : '#ffffff';
  const ink = t.dark ? '#f3f3f6' : '#1a1c22';
  const sub = t.dark ? 'rgba(240,240,250,0.55)' : 'rgba(26,28,34,0.5)';
  const line = t.dark ? 'rgba(255,255,255,0.09)' : 'rgba(20,22,30,0.08)';
  const tileBase = t.dark ? '#202028' : '#eef0f4';
  const tileStripe = t.dark ? '#26262f' : '#f5f6f9';
  const chipBg = t.dark ? 'rgba(255,255,255,0.06)' : '#f3f4f7';
  const mono = GW.mono;
  const interactive = typeof onClick === 'function';
  return (
    <div
      onClick={onClick}
      role={interactive ? 'button' : undefined}
      aria-pressed={interactive ? active : undefined}
      title={interactive ? `Preview ${t.name}` : undefined}
      style={{ width, height: h, borderRadius: 26, overflow: 'hidden', background: surface, border: `1px solid ${line}`,
        boxShadow: active
          ? `0 0 0 2px ${t.accent}, 0 18px 44px -20px ${gwRgba(t.accent, 0.5)}`
          : (t.dark ? '0 18px 44px -22px rgba(10,10,20,0.6)' : '0 18px 44px -24px rgba(20,22,50,0.34)'),
        display: 'flex', flexDirection: 'column', position: 'relative',
        cursor: interactive ? 'pointer' : 'default',
        transform: active ? 'translateY(-4px)' : 'none', transition: 'transform .2s ease, box-shadow .2s ease', ...style }}>
      {/* header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '14px 13px 10px' }}>
        <div style={{ width: 24, height: 24, borderRadius: 7, background: t.accent, flex: '0 0 auto', boxShadow: `0 2px 6px ${gwRgba(t.accent, 0.4)}` }}></div>
        <div style={{ minWidth: 0, flex: 1 }}>
          {showName
            ? <div style={{ fontFamily: GW.sans, fontSize: 11, fontWeight: 650, color: ink, letterSpacing: -0.2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{t.name}</div>
            : <div style={{ height: 7, width: '70%', borderRadius: 4, background: t.dark ? 'rgba(255,255,255,0.16)' : 'rgba(20,22,30,0.14)' }}></div>}
          <div style={{ fontFamily: mono, fontSize: 7, letterSpacing: 0.4, color: sub, textTransform: 'uppercase', marginTop: 2 }}>Member app</div>
        </div>
        <div style={{ width: 18, height: 18, borderRadius: 999, background: chipBg }}></div>
      </div>

      {/* hero media tile, brand-tinted */}
      <div style={{ margin: '0 11px', borderRadius: 16, overflow: 'hidden', flex: 1, minHeight: 0, position: 'relative', background: `repeating-linear-gradient(135deg, ${tileBase} 0 9px, ${tileStripe} 9px 18px)` }}>
        <div style={{ position: 'absolute', inset: 0, background: `linear-gradient(160deg, ${gwRgba(t.accent, t.dark ? 0.34 : 0.18)}, transparent 64%)` }}></div>
        <div style={{ position: 'absolute', top: '40%', left: '50%', transform: 'translate(-50%,-50%)', width: 36, height: 36, borderRadius: 999, background: t.dark ? 'rgba(255,255,255,0.92)' : surface, boxShadow: '0 6px 16px rgba(0,0,0,0.18)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <svg width="12" height="14" viewBox="0 0 18 20" fill={t.accent}><path d="M2 2.5v15a1 1 0 001.5.87l13-7.5a1 1 0 000-1.74l-13-7.5A1 1 0 002 2.5z"/></svg>
        </div>
        <div style={{ position: 'absolute', left: 8, top: 8, padding: '3px 7px', borderRadius: 999, background: gwRgba(t.accent, 0.92) }}>
          <span style={{ fontFamily: mono, fontSize: 6.5, letterSpacing: 0.4, color: '#fff', textTransform: 'uppercase' }}>For you</span>
        </div>
        <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, padding: '20px 10px 9px', background: 'linear-gradient(to top, rgba(12,12,16,0.72), transparent)' }}>
          <div style={{ height: 7, width: '78%', borderRadius: 4, background: 'rgba(255,255,255,0.92)' }}></div>
          <div style={{ height: 5, width: '52%', borderRadius: 4, background: 'rgba(255,255,255,0.5)', marginTop: 5 }}></div>
        </div>
      </div>

      {/* chips */}
      <div style={{ display: 'flex', gap: 7, padding: '10px 11px 0' }}>
        {[0, 1].map((i) => (
          <div key={i} style={{ flex: 1, height: 30, borderRadius: 9, background: chipBg, display: 'flex', alignItems: 'center', padding: '0 8px', gap: 6 }}>
            <div style={{ width: 14, height: 14, borderRadius: 5, background: gwRgba(t.accent, t.dark ? 0.5 : 0.22) }}></div>
            <div style={{ height: 5, flex: 1, borderRadius: 3, background: t.dark ? 'rgba(255,255,255,0.16)' : 'rgba(20,22,30,0.13)' }}></div>
          </div>
        ))}
      </div>

      {/* brand CTA pill */}
      <div style={{ padding: '10px 11px 13px' }}>
        <div style={{ height: 30, borderRadius: 10, background: t.accent, boxShadow: `0 5px 14px -4px ${gwRgba(t.accent, 0.6)}`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <div style={{ height: 6, width: 52, borderRadius: 4, background: 'rgba(255,255,255,0.92)' }}></div>
        </div>
      </div>
    </div>
  );
}

window.ThemePreview = ThemePreview;
