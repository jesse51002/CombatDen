// brand.jsx — §3 "Your brand, everywhere": split layout. Copy on the left
// (heading + body + Browse themes button), and a transparent looping video on
// the right showing the same member app fanned across three gym brand themes.
// The phones are baked into the clip on an alpha background, so it sits
// seamlessly over the page. Plays only while in view (shared landing rule).
// Copy from COPY.brand. Exports BrandSection.

function BrandSection() {
  const c = COPY.brand;
  const videoRef = React.useRef(null);
  useVideoInView(videoRef); // play only while in view + restart on exit (shared landing rule)
  return (
    <section id="themes" data-screen-label="03 Your brand" style={{ position: 'relative', background: GW.bg, fontFamily: GW.sans, padding: '40px 0 130px' }}>
      <div style={{ maxWidth: GW.maxW, margin: '0 auto', padding: '0 32px', display: 'grid', gridTemplateColumns: '1fr 1fr', alignItems: 'center', gap: 24 }}>
        {/* left — copy */}
        <div>
          <h2 style={{ margin: 0, fontSize: 'clamp(30px,3.4vw,44px)', lineHeight: 1.08, letterSpacing: -1.5, fontWeight: 600, color: GW.ink, textWrap: 'balance' }}>{c.heading}</h2>
          <p style={{ margin: '18px 0 0', maxWidth: 460, fontSize: 'clamp(16px,1.7vw,19px)', lineHeight: 1.5, fontWeight: 450, color: GW.inkSoft, textWrap: 'pretty' }}>
            {c.body}
          </p>
          <div style={{ marginTop: 28 }}><GWButton label={c.button} href={c.themeLibraryUrl} arrow newTab={false} /></div>
        </div>
        {/* right — transparent looping video: the app shown across three brand
            themes. The clip carries its own alpha, so no background/frame here. */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <video
            ref={videoRef}
            src="assets/landing/gymworld-3phones.webm"
            loop
            muted
            playsInline
            preload="auto"
            aria-label="The member app shown in three gym brand themes"
            style={{ width: '100%', maxWidth: 520, aspectRatio: '1134 / 1213', height: 'auto', display: 'block' }}
          />
        </div>
      </div>
    </section>
  );
}

window.BrandSection = BrandSection;
