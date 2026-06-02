// hero.jsx — §1 Hero: editorial headline, gradient mesh, and a trio of phones
// showing REAL app screenshots from assets/landing/screenshots/. The phones are
// rewards (left), home (center), videos (right), and all three cycle through the
// gyms together every 5s with an opacity crossfade. Copy from COPY.hero.
// Exports HeroSection.

const HERO_GYMS = ["yoga", "muaythai", "bjj", "barre", "boxing", "crossfit"];
const HERO_SHOTS = "assets/landing/screenshots";
const HERO_SEG = 5000; // ms each gym holds before cycling to the next
const HERO_FADE = "0.6s"; // crossfade between gyms

// ScreenshotPhone — shared PhoneFrame wrapping a stack of real screenshots for
// one screen type ('home' | 'videos' | 'rewards'). All gym images are stacked;
// the active `gym` layer crossfades to opacity 1 so the screenshot swaps with no
// flash (same approach as the §4 feed thumbnails). `seen` gates loading per gym
// so the ~16MB of full-res PNGs load progressively (the incoming gym is
// preloaded one tick ahead) instead of all at once on first paint. No dynamic
// island — the screenshots carry their own status bar.
function ScreenshotPhone({
  screen,
  gym = 0,
  seen,
  width = 300,
  tilt = "none",
  glow = true,
}) {
  return (
    <PhoneFrame width={width} tilt={tilt} glow={glow} island={false}>
      <div
        style={{ position: "relative", height: "100%", background: "#0a0a0c" }}
      >
        {HERO_GYMS.map((g, i) => (
          <img
            key={g}
            src={seen.has(i) ? `${HERO_SHOTS}/${screen}-${g}.png` : undefined}
            alt=""
            style={{
              position: "absolute",
              inset: 0,
              width: "100%",
              height: "100%",
              objectFit: "cover",
              display: "block",
              opacity: i === gym ? 1 : 0,
              transition: `opacity ${HERO_FADE} ease`,
            }}
          />
        ))}
      </div>
    </PhoneFrame>
  );
}

function HeroSection() {
  const n = HERO_GYMS.length;
  const isMobile = useIsMobile();
  const [gym, setGym] = React.useState(0);
  // Lazy, progressive loading: an image only gets a real src once its gym is
  // "seen". Seed {0,1} and queue one gym ahead each tick, so the incoming gym is
  // always preloaded before it shows (no flash) without pulling all ~16MB up front.
  const [seen, setSeen] = React.useState(() => new Set([0, 1 % n]));
  // Cycle only while the hero is actually in view (shared 25% gate), so it pauses
  // once scrolled past instead of churning off-screen.
  const heroRef = React.useRef(null);
  const inView = React.useRef(true); // hero is on-screen at load
  React.useEffect(() => {
    const el = heroRef.current;
    const io = new IntersectionObserver((e) => { inView.current = e[0].isIntersecting; }, { rootMargin: IN_VIEW_MARGIN });
    if (el) io.observe(el);
    const id = setInterval(() => {
      if (!inView.current) return;
      setGym((p) => {
        const next = (p + 1) % n;
        setSeen((s) => new Set([...s, next, (next + 1) % n]));
        return next;
      });
    }, HERO_SEG);
    return () => { io.disconnect(); clearInterval(id); };
  }, [n]);

  return (
    <section
      ref={heroRef}
      data-screen-label="01 Hero"
      style={{
        position: "relative",
        overflow: "hidden",
        background: GW.bg,
        fontFamily: GW.sans,
        marginTop: -68,
      }}
    >
      {/* gradient mesh */}
      <GWGlow
        style={{
          top: -300,
          left: -160,
          width: 820,
          height: 760,
          background: `radial-gradient(50% 50% at 50% 50%, ${GW.accentGlow}, transparent 70%)`,
        }}
      />
      <GWGlow
        style={{
          top: -240,
          right: -180,
          width: 760,
          height: 740,
          background: `radial-gradient(50% 50% at 50% 50%, ${GW.cyanGlow}, transparent 70%)`,
        }}
      />
      <GWDotGrid />

      <div
        style={{
          position: "relative",
          zIndex: 3,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          textAlign: "center",
          padding: isMobile ? "76px 20px 0" : "92px 32px 0",
          maxWidth: 940,
          margin: "0 auto",
        }}
      >
        <h1
          style={{
            margin: 0,
            fontSize: "clamp(40px, 6vw, 68px)",
            lineHeight: 1.0,
            fontWeight: 600,
            letterSpacing: -2.4,
            color: GW.ink,
            maxWidth: 840,
            textWrap: "balance",
          }}
        >
          {COPY.hero.headline}
        </h1>
        <p
          style={{
            margin: "24px 0 0",
            fontSize: "clamp(17px, 2vw, 20px)",
            lineHeight: 1.5,
            color: GW.inkSoft,
            maxWidth: 600,
            fontWeight: 450,
            textWrap: "pretty",
          }}
        >
          {COPY.hero.subline}
        </p>
        <div style={{ marginTop: 30 }}>
          <GWButton size="lg" href="#book" newTab={false} />
        </div>
        <div style={{ marginTop: 18 }}>
          <GWDisclaimer />
        </div>
      </div>

      {/* phone trio (real screenshots): rewards · home · videos, cycling all gyms
          together every 5s. Tops fully visible, bottoms bleed off & fade into the
          next section. The whole trio scales down on mobile so all three still fit
          a phone screen (sizes/overlap shrink proportionally). */}
      <div style={{ position: "relative", zIndex: 2, marginTop: isMobile ? 36 : 60 }}>
        <div
          style={{
            display: "flex",
            justifyContent: "center",
            alignItems: "flex-start",
            // shorter than the phone height (~70%) so the bottoms bleed off and
            // fade into the next section, same as desktop
            height: isMobile ? 212 : 430,
            overflow: "hidden",
          }}
        >
          <div
            style={{
              transform: `translateY(${isMobile ? 28 : 56}px)`,
              marginRight: isMobile ? -22 : -44,
              zIndex: 1,
            }}
          >
            <ScreenshotPhone
              screen="rewards"
              gym={gym}
              seen={seen}
              width={isMobile ? 122 : 250}
              tilt="left"
              glow={false}
            />
          </div>
          <div style={{ zIndex: 2 }}>
            <ScreenshotPhone
              screen="home"
              gym={gym}
              seen={seen}
              width={isMobile ? 148 : 300}
              tilt="none"
              glow={true}
            />
          </div>
          <div
            style={{
              transform: `translateY(${isMobile ? 28 : 56}px)`,
              marginLeft: isMobile ? -22 : -44,
              zIndex: 1,
            }}
          >
            <ScreenshotPhone
              screen="videos"
              gym={gym}
              seen={seen}
              width={isMobile ? 122 : 250}
              tilt="right"
              glow={false}
            />
          </div>
        </div>
        {/* soft fade so the phones dissolve into the next section */}
        <div
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            bottom: 0,
            height: isMobile ? 100 : 150,
            background: `linear-gradient(to top, ${GW.bg} 12%, transparent)`,
            pointerEvents: "none",
            zIndex: 3,
          }}
        ></div>
      </div>
    </section>
  );
}

window.HeroSection = HeroSection;
