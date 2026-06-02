// footer.jsx — §8 closing CTA + booking form (shared by landing + pricing).
// Ported from the handoff footer-cta2.jsx: same Google Form POST + Calendly
// open behavior the founder's old footer used. Copy from COPY.footer; brand
// from BRAND. Exports FooterSection to window.

const CALENDLY_URL = 'https://calendly.com/jessemusa2/30min';
const GOOGLE_FORM_ACTION = 'https://docs.google.com/forms/d/e/1FAIpQLSeaRZoyYuP9YKD-oDu19y9pb11-iOLcgWdCO2WfrxRCGk7uaA/formResponse';
const FORM_ENTRY_IDS = { name: 'entry.643842673', gym: 'entry.714252564', email: 'entry.1844120895' };

function FooterSection() {
  const isMobile = useIsMobile();
  const [form, setForm] = React.useState({ name: '', email: '', gym: '' });
  const [status, setStatus] = React.useState('idle'); // idle | submitting | submitted | error
  const onChange = (k) => (e) => setForm((f) => ({ ...f, [k]: e.target.value }));
  const [focus, setFocus] = React.useState('');
  const c = COPY.footer;

  async function onSubmit(e) {
    e.preventDefault();
    if (status === 'submitting') return;
    if (!form.name.trim() || !form.email.trim() || !form.gym.trim()) return;
    setStatus('submitting');
    let ok = true;
    try {
      const body = new URLSearchParams();
      body.append(FORM_ENTRY_IDS.name, form.name);
      body.append(FORM_ENTRY_IDS.gym, form.gym);
      body.append(FORM_ENTRY_IDS.email, form.email);
      await fetch(GOOGLE_FORM_ACTION, { method: 'POST', mode: 'no-cors', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: body.toString() });
    } catch (_) { ok = false; }
    setStatus(ok ? 'submitted' : 'error');
    const u = new URL(CALENDLY_URL);
    u.searchParams.set('name', form.name);
    u.searchParams.set('email', form.email);
    u.searchParams.set('a1', form.gym);
    window.open(u.toString(), '_blank', 'noopener,noreferrer');
  }
  const submitting = status === 'submitting';
  const submitted = status === 'submitted';

  const input = (key, type, placeholder) => (
    <input
      type={type} placeholder={placeholder} value={form[key]} onChange={onChange(key)} required
      onFocus={() => setFocus(key)} onBlur={() => setFocus('')}
      style={{ width: '100%', padding: '15px 16px', fontFamily: GW.sans, fontSize: 15, fontWeight: 450, color: GW.ink,
        background: '#fff', border: `1px solid ${focus === key ? GW.accent : GW.line}`, borderRadius: 12, outline: 'none',
        boxShadow: focus === key ? `0 0 0 3px ${GW.accent}22` : '0 1px 2px rgba(20,22,40,0.03)', boxSizing: 'border-box', transition: 'border-color .15s, box-shadow .15s' }}
    />
  );

  return (
    <footer id="book" data-screen-label="08 Footer" style={{ width: '100%', background: GW.bg, fontFamily: GW.sans, position: 'relative' }}>
      <GWGlow style={{ top: -120, left: '50%', transform: 'translateX(-50%)', width: 900, height: 520, background: `radial-gradient(50% 50% at 50% 50%, ${GW.accentGlow}, transparent 72%)` }} />
      <div style={{ position: 'relative', zIndex: 1, maxWidth: GW.maxW, margin: '0 auto', padding: isMobile ? '80px 20px 40px' : '104px 32px 48px' }}>
        <div style={{ display: 'flex', justifyContent: 'center' }}>
          {/* one cohesive booking card: headline + reassurance + form together */}
          <form onSubmit={onSubmit} style={{ background: 'linear-gradient(180deg, #ffffff, #f5f7fb)', border: '1px solid rgba(20,22,40,0.07)', borderRadius: 24, boxShadow: '0 1px 2px rgba(20,22,40,0.03), 0 24px 54px -30px rgba(20,22,50,0.22), inset 0 1px 0 rgba(255,255,255,0.9)', padding: isMobile ? '32px 22px 28px' : '44px 64px 40px', display: 'flex', flexDirection: 'column', gap: 12, width: '100%', maxWidth: 800, textAlign: 'left' }}>
            {/* card header */}
            <div style={{ textAlign: 'center', marginBottom: 10 }}>
              <h2 style={{ margin: 0, fontSize: 'clamp(27px,3.2vw,40px)', lineHeight: 1.04, letterSpacing: -1.4, fontWeight: 600, color: GW.ink, textWrap: 'balance' }}>{c.headline}</h2>
              <div style={{ marginTop: 12, display: 'inline-flex', alignItems: 'center', gap: 9, color: GW.inkFaint }}>
                <svg width="15" height="15" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5"><path d="M8 1.5l5.5 2v4c0 3.4-2.4 5.7-5.5 6.9C4.9 13.2 2.5 10.9 2.5 7.5v-4z" strokeLinejoin="round"/><path d="M5.8 8l1.6 1.6L10.4 6" strokeLinecap="round" strokeLinejoin="round"/></svg>
                <span style={{ fontFamily: GW.mono, fontSize: 12, letterSpacing: 0.1 }}>{c.reassurance}</span>
              </div>
            </div>
            {input('name', 'text', c.placeholders.name)}
            {input('email', 'email', c.placeholders.email)}
            {input('gym', 'text', c.placeholders.gym)}
            <button type="submit" disabled={submitting || submitted} style={{
              marginTop: 4, padding: '15px 22px', borderRadius: 12, border: 'none', cursor: submitting || submitted ? 'default' : 'pointer',
              fontFamily: GW.sans, fontSize: 15.5, fontWeight: 600, letterSpacing: -0.1, whiteSpace: 'nowrap',
              color: submitted ? GW.accentDark : '#fff',
              background: submitted ? GW.accentSoft : `linear-gradient(180deg, ${GW.accent}, ${GW.accentDark})`,
              boxShadow: submitted ? 'none' : '0 1px 2px rgba(15,45,95,0.3), 0 10px 24px -8px rgba(30,80,160,0.5), inset 0 1px 0 rgba(255,255,255,0.28)',
              opacity: submitting ? 0.75 : 1, transition: 'all .2s ease' }}>
              {submitting ? c.submitting : submitted ? c.submitted : c.submit}
            </button>
            {status === 'error' && (
              <div style={{ fontSize: 13, color: '#C0392B', marginTop: 2 }}>{c.error}</div>
            )}
          </form>
        </div>

        {/* slim bottom bar */}
        <div style={{ marginTop: 72, paddingTop: 26, borderTop: `1px solid ${GW.line}`, display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 16, flexWrap: 'wrap' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <img src="assets/landing/logo_tiny.png" alt="" style={{ height: 28, width: 'auto', display: 'block' }} />
            <span style={{ fontSize: 15, fontWeight: 650, letterSpacing: -0.3, color: GW.ink }}>{BRAND}</span>
          </div>
          <span style={{ fontFamily: GW.mono, fontSize: 11, letterSpacing: 0.3, color: GW.inkFaint }}>{COPY.footer.copyright} {BRAND}</span>
        </div>
      </div>
    </footer>
  );
}

window.FooterSection = FooterSection;
