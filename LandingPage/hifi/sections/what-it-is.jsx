// what-it-is.jsx — §2 "What it is": one centered two-tone statement.
// No heading — the statement IS the section. Copy from COPY.whatItIs.
// Exports WhatItIsSection.

function WhatItIsSection() {
  const c = COPY.whatItIs;
  return (
    <section data-screen-label="02 What it is" style={{ position: 'relative', background: GW.bg, fontFamily: GW.sans }}>
      <div style={{ maxWidth: GW.maxW, margin: '0 auto', padding: '120px 32px 150px' }}>
        <p style={{ margin: '0 auto', maxWidth: 860, textAlign: 'center', fontSize: 'clamp(28px,3.6vw,46px)', lineHeight: 1.18, letterSpacing: -1.4, fontWeight: 550, textWrap: 'balance' }}>
          <span style={{ color: GW.ink }}>{c.lead}</span><span style={{ color: GW.accent }}>{c.leadAccent}</span>{' '}
          <span style={{ color: GW.inkFaint, fontWeight: 450 }}>{c.tail}</span>
        </p>
      </div>
    </section>
  );
}

window.WhatItIsSection = WhatItIsSection;
