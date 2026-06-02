// pricing-table.jsx — Pricing page: a frosted comparison panel, 4 tiers, the
// featured "Customization" column raised with a "Most popular" badge.
// Copy/data from COPY.pricing. Exports PricingSection.

function PriceCheck() {
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', justifyContent: 'center', width: 24, height: 24, borderRadius: 999, background: GW.accentSoft }}>
      <svg width="13" height="13" viewBox="0 0 14 14" fill="none" stroke={GW.accentDark} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M2.5 7.4l2.7 2.7L11.5 4"/></svg>
    </span>
  );
}
function PriceDash() {
  return <span style={{ display: 'inline-block', width: 14, height: 2, borderRadius: 2, background: GW.line }}></span>;
}

function PriceCell({ v, featured }) {
  let content;
  if (v === true) content = <PriceCheck />;
  else if (v === false) content = <PriceDash />;
  else content = <span style={{ fontSize: 13.5, fontWeight: 600, color: GW.ink, letterSpacing: -0.1 }}>{v}</span>;
  return (
    <td style={{ textAlign: 'center', padding: '17px 20px', verticalAlign: 'middle',
      background: featured ? 'rgba(42,103,189,0.045)' : 'transparent',
      borderLeft: featured ? `1px solid ${GW.accent}22` : '1px solid transparent', borderRight: featured ? `1px solid ${GW.accent}22` : '1px solid transparent' }}>
      {content}
    </td>
  );
}

// Mobile pricing: each tier as its own stacked card (name, price, blurb, the full
// feature list with that tier's value, CTA). Transposes COPY.pricing.rows/vals so
// the comparison table doesn't force horizontal scrolling on a phone.
function StackedTiers({ tiers, rows, ctaPaid, ctaEnterprise, mostPopular }) {
  const valNode = (v) => {
    if (v === true) return <PriceCheck />;
    if (v === false) return <PriceDash />;
    return <span style={{ fontSize: 13.5, fontWeight: 600, color: GW.ink, letterSpacing: -0.1 }}>{v}</span>;
  };
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>
      {tiers.map((t, ci) => (
        <div key={t.id} style={{ position: 'relative', borderRadius: 22, padding: '24px 20px 22px',
          background: t.featured ? 'linear-gradient(180deg, rgba(42,103,189,0.08), rgba(255,255,255,0.7))' : 'linear-gradient(180deg, rgba(255,255,255,0.75), rgba(246,248,252,0.5))',
          border: `1px solid ${t.featured ? GW.accent + '33' : 'rgba(20,22,40,0.07)'}`,
          boxShadow: t.featured ? `0 0 0 1px ${GW.accent}22, 0 24px 50px -30px rgba(30,80,160,0.4)` : '0 1px 2px rgba(20,22,40,0.03), 0 20px 44px -32px rgba(20,22,50,0.2)' }}>
          {/* header (centered) */}
          <div style={{ textAlign: 'center' }}>
            {t.featured && <div style={{ display: 'inline-block', fontFamily: GW.mono, fontSize: 9.5, fontWeight: 600, letterSpacing: 0.5, textTransform: 'uppercase', color: '#fff', background: `linear-gradient(180deg, ${GW.accent}, ${GW.accentDark})`, padding: '3px 9px', borderRadius: 999, marginBottom: 12 }}>{mostPopular}</div>}
            <div style={{ fontSize: 18, fontWeight: 650, color: GW.ink, letterSpacing: -0.3 }}>{t.name}</div>
            <div style={{ marginTop: 6, display: 'flex', alignItems: 'baseline', justifyContent: 'center', gap: 2 }}>
              <span style={{ fontSize: 30, fontWeight: 700, color: t.featured ? GW.accentDark : GW.ink, letterSpacing: -1 }}>{t.price}</span>
              <span style={{ fontSize: 14, fontWeight: 500, color: GW.inkFaint }}>{t.cadence}</span>
            </div>
            <div style={{ marginTop: 5, fontSize: 12.5, color: GW.inkFaint, fontWeight: 450 }}>{t.blurb}</div>
          </div>
          {/* features */}
          <div style={{ marginTop: 16 }}>
            {rows.map((r, ri) => {
              const v = r.vals[ci];
              const included = v !== false;
              return (
                <div key={ri} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 14, padding: '11px 0', borderTop: `1px solid ${GW.lineSoft}` }}>
                  <div style={{ minWidth: 0 }}>
                    <div style={{ fontSize: 14, fontWeight: 500, color: included ? GW.ink : GW.inkFaint, letterSpacing: -0.1 }}>{r.label}</div>
                    {r.sub && <div style={{ fontSize: 11.5, color: GW.inkFaint, marginTop: 1 }}>{r.sub}</div>}
                  </div>
                  <div style={{ flex: '0 0 auto', display: 'flex', alignItems: 'center', justifyContent: 'flex-end' }}>{valNode(v)}</div>
                </div>
              );
            })}
          </div>
          {/* CTA */}
          <a href="#book" style={{ textDecoration: 'none' }}>
            <span style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', width: '100%', boxSizing: 'border-box', marginTop: 18, whiteSpace: 'nowrap',
              fontFamily: GW.sans, fontSize: 14.5, fontWeight: 600, letterSpacing: -0.1, padding: '13px 18px', borderRadius: 12, cursor: 'pointer',
              color: t.featured ? '#fff' : GW.ink,
              background: t.featured ? `linear-gradient(180deg, ${GW.accent}, ${GW.accentDark})` : GW.surface,
              border: t.featured ? 'none' : `1px solid ${GW.line}`,
              boxShadow: t.featured ? '0 1px 2px rgba(15,45,95,0.3), 0 8px 20px -8px rgba(30,80,160,0.5), inset 0 1px 0 rgba(255,255,255,0.28)' : '0 1px 2px rgba(20,22,40,0.05)' }}>
              {t.id === 'ent' ? ctaEnterprise : ctaPaid}
            </span>
          </a>
        </div>
      ))}
    </div>
  );
}

function PricingSection() {
  const { title, compareLabel, mostPopular, tiers, rows, ctaPaid, ctaEnterprise } = COPY.pricing;
  const isMobile = useIsMobile();
  return (
    <section data-screen-label="Pricing" style={{ width: '100%', background: GW.bg, fontFamily: GW.sans, position: 'relative', overflow: 'visible', marginTop: -68 }}>
      <GWGlow style={{ top: -200, left: '50%', transform: 'translateX(-50%)', width: 1000, height: 560, background: `radial-gradient(50% 50% at 50% 50%, ${GW.accentGlow}, transparent 72%)` }} />
      <GWDotGrid color="rgba(20,22,40,0.05)" fade="radial-gradient(120% 80% at 50% 0%, #000 30%, transparent 75%)" />

      <div style={{ position: 'relative', zIndex: 1, maxWidth: 1120, margin: '0 auto', padding: isMobile ? '104px 20px 40px' : '128px 32px 40px' }}>
        {/* title */}
        <h1 style={{ margin: '0 auto 48px', textAlign: 'center', maxWidth: 640, fontSize: 'clamp(34px,4.4vw,56px)', lineHeight: 1.02, letterSpacing: -2.2, fontWeight: 600, color: GW.ink, textWrap: 'balance' }}>{title}</h1>

        {isMobile ? (
          <StackedTiers tiers={tiers} rows={rows} ctaPaid={ctaPaid} ctaEnterprise={ctaEnterprise} mostPopular={mostPopular} />
        ) : (
        /* comparison table */
        <div style={{ overflow: 'hidden', borderRadius: 26, background: 'linear-gradient(180deg, rgba(255,255,255,0.6), rgba(246,248,252,0.42))', backdropFilter: 'blur(20px) saturate(150%)', WebkitBackdropFilter: 'blur(20px) saturate(150%)', boxShadow: '0 0 0 1px rgba(20,22,40,0.05), 0 1px 1px rgba(20,22,40,0.03), 0 50px 90px -52px rgba(20,22,50,0.3), inset 0 1px 0 rgba(255,255,255,0.7)' }}>
          <div style={{ overflowX: 'auto' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse', minWidth: 860 }}>
            <thead>
              <tr>
                <th style={{ textAlign: 'left', padding: '26px 24px 22px', verticalAlign: 'bottom', width: '28%' }}>
                  <span style={{ fontFamily: GW.mono, fontSize: 10.5, letterSpacing: 0.6, color: GW.inkFaint, textTransform: 'uppercase' }}>{compareLabel}</span>
                </th>
                {tiers.map((t) => (
                  <th key={t.id} style={{ padding: '22px 18px 20px', verticalAlign: 'bottom', textAlign: 'center', position: 'relative',
                    background: t.featured ? 'linear-gradient(180deg, rgba(42,103,189,0.1), rgba(42,103,189,0.03))' : 'transparent',
                    borderLeft: t.featured ? `1px solid ${GW.accent}22` : 'none', borderRight: t.featured ? `1px solid ${GW.accent}22` : 'none',
                    boxShadow: t.featured ? `inset 0 2px 0 ${GW.accent}` : 'none',
                    borderTopLeftRadius: t.featured ? 16 : 0, borderTopRightRadius: t.featured ? 16 : 0 }}>
                    {t.featured && <div style={{ display: 'inline-block', fontFamily: GW.mono, fontSize: 9.5, fontWeight: 600, letterSpacing: 0.5, textTransform: 'uppercase', color: '#fff', background: `linear-gradient(180deg, ${GW.accent}, ${GW.accentDark})`, padding: '3px 9px', borderRadius: 999, marginBottom: 10 }}>{mostPopular}</div>}
                    <div style={{ fontSize: 15, fontWeight: 650, color: GW.ink, letterSpacing: -0.2 }}>{t.name}</div>
                    <div style={{ marginTop: 6, display: 'flex', alignItems: 'baseline', justifyContent: 'center', gap: 1 }}>
                      <span style={{ fontSize: 26, fontWeight: 700, color: t.featured ? GW.accentDark : GW.ink, letterSpacing: -1 }}>{t.price}</span>
                      <span style={{ fontSize: 13, fontWeight: 500, color: GW.inkFaint }}>{t.cadence}</span>
                    </div>
                    <div style={{ marginTop: 5, fontSize: 11.5, color: GW.inkFaint, fontWeight: 450 }}>{t.blurb}</div>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((r, ri) => (
                <tr key={ri} style={{ borderTop: `1px solid ${GW.lineSoft}` }}>
                  <td style={{ textAlign: 'left', padding: '16px 24px', verticalAlign: 'middle' }}>
                    <div style={{ fontSize: 14.5, fontWeight: 600, color: GW.ink, letterSpacing: -0.2 }}>{r.label}</div>
                    {r.sub && <div style={{ fontSize: 12, color: GW.inkFaint, marginTop: 2 }}>{r.sub}</div>}
                  </td>
                  {r.vals.map((v, ci) => <PriceCell key={ci} v={v} featured={tiers[ci].featured} />)}
                </tr>
              ))}
              {/* CTA row */}
              <tr style={{ borderTop: `1px solid ${GW.line}` }}>
                <td style={{ padding: '22px 24px' }}></td>
                {tiers.map((t) => (
                  <td key={t.id} style={{ padding: '22px 16px', textAlign: 'center', verticalAlign: 'top',
                    background: t.featured ? 'rgba(42,103,189,0.06)' : 'transparent',
                    borderLeft: t.featured ? `1px solid ${GW.accent}22` : 'none', borderRight: t.featured ? `1px solid ${GW.accent}22` : 'none',
                    borderBottomLeftRadius: t.featured ? 16 : 0, borderBottomRightRadius: t.featured ? 16 : 0 }}>
                    <a href="#book" style={{ textDecoration: 'none' }}>
                      <span style={{ display: 'inline-flex', alignItems: 'center', justifyContent: 'center', whiteSpace: 'nowrap',
                        fontFamily: GW.sans, fontSize: 13.5, fontWeight: 600, letterSpacing: -0.1, padding: '11px 16px', borderRadius: 11, cursor: 'pointer',
                        color: t.featured ? '#fff' : GW.ink,
                        background: t.featured ? `linear-gradient(180deg, ${GW.accent}, ${GW.accentDark})` : GW.surface,
                        border: t.featured ? 'none' : `1px solid ${GW.line}`,
                        boxShadow: t.featured ? '0 1px 2px rgba(15,45,95,0.3), 0 8px 20px -8px rgba(30,80,160,0.5), inset 0 1px 0 rgba(255,255,255,0.28)' : '0 1px 2px rgba(20,22,40,0.05)' }}>
                        {t.id === 'ent' ? ctaEnterprise : ctaPaid}
                      </span>
                    </a>
                  </td>
                ))}
              </tr>
            </tbody>
          </table>
          </div>
        </div>
        )}
      </div>
    </section>
  );
}

window.PricingSection = PricingSection;
