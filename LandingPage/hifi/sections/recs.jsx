// recs.jsx — §5 "Perfectly timed content": a phone plays the real app screen-
// recording (a class booking, then the matched warm-up video surfaces at the right
// moment). Copy is header + subheader (COPY.recs). The phone screen is sized to the
// video's exact aspect ratio (1080x2340), so the clip fills it with no cropping. The
// clip plays only in view and restarts on exit via the shared useVideoInView hook.
// Exports RecsSection.

const REC_VIDEO_WEBM = 'assets/landing/perfectly-timed-vinyasa.webm';

// phone playing the screen-recording. The screen hugs the video at its native
// aspect (width set, height auto), so the frame fits the clip exactly — no crop.
function RecVideoPhone({ width = 274, videoRef }) {
  return (
    <div style={{ borderRadius: 46, background: '#c7cbd2', padding: 11,
      boxShadow: '0 2px 4px rgba(20,22,30,0.22), 0 44px 80px -28px rgba(20,22,40,0.45), inset 0 0 0 1px rgba(255,255,255,0.14)' }}>
      <div style={{ width, borderRadius: 36, overflow: 'hidden', background: '#000', boxShadow: 'inset 0 0 0 2px rgba(0,0,0,0.85)' }}>
        <video ref={videoRef} src={REC_VIDEO_WEBM} loop muted playsInline preload="auto" aria-label="Perfectly timed content demo"
          style={{ width: '100%', height: 'auto', display: 'block' }} />
      </div>
    </div>
  );
}

function RecsSection() {
  const videoRef = React.useRef(null);
  useVideoInView(videoRef); // play only while in view + restart on exit (shared landing rule)
  return (
    <section data-screen-label="05 Perfectly timed" style={{ width: '100%', background: GW.bg, fontFamily: GW.sans, overflow: 'hidden' }}>
      <div style={{ position: 'relative', maxWidth: GW.maxW, margin: '0 auto', padding: '96px 32px 104px' }}>
        <GWGlow style={{ top: '50%', left: '50%', transform: 'translate(-50%,-50%)', width: 820, height: 560, background: `radial-gradient(50% 50% at 50% 50%, ${GW.accentGlow}, transparent 70%)` }} />
        <GWDotGrid color="rgba(20,22,40,0.05)" fade="radial-gradient(80% 80% at 50% 50%, #000 30%, transparent 80%)" />

        {/* copy (centered, above the phone) */}
        <div style={{ position: 'relative', zIndex: 1, textAlign: 'center', maxWidth: 640, margin: '0 auto' }}>
          <h2 style={{ margin: 0, fontSize: 'clamp(30px,3.4vw,44px)', lineHeight: 1.08, letterSpacing: -1.5, fontWeight: 600, color: GW.ink, textWrap: 'balance' }}>{COPY.recs.header}</h2>
          <p style={{ margin: '16px auto 0', maxWidth: 520, fontSize: 'clamp(16px,1.8vw,20px)', lineHeight: 1.5, fontWeight: 450, color: GW.inkSoft, textWrap: 'pretty' }}>{COPY.recs.subheader}</p>
        </div>

        {/* phone (centered, below) */}
        <div style={{ position: 'relative', zIndex: 1, display: 'flex', justifyContent: 'center', marginTop: 'clamp(40px,5vw,64px)' }}>
          <RecVideoPhone width={274} videoRef={videoRef} />
        </div>
      </div>
    </section>
  );
}

window.RecsSection = RecsSection;
