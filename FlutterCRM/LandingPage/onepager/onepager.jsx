// CombatDen — Printable One Pager (Editorial · Paper palette)
// One US Letter portrait page (816 × 1056 @ 96dpi) for sales leave-behinds.
// Three sections: Engagement · Loyalty · Branded App.

const PAGE_W = 816;
const PAGE_H = 1056;

// Body sections (Engagement · Loyalty · Branded) all use a 2-col layout with
// the left text block at this fixed width. Hardcoded so the eyebrow / headline
// stack is visually aligned across every section.
const SECTION_TEXT_COL_W = 280;
const SECTION_COL_GAP = 32;

// ---------- Palette ----------
const P = {
  bg: "#F4F3EE",
  bg2: "#EAE7DD",
  surface: "#FFFFFF",
  fg1: "#0F1316",
  fg2: "rgba(15,19,22,0.72)",
  fg3: "rgba(15,19,22,0.55)",
  fg4: "rgba(15,19,22,0.30)",
  hairline: "rgba(15,19,22,0.14)",
  divider: "rgba(15,19,22,0.20)",
  orange: "#E55A1C",
  orangeSoft: "rgba(229,90,28,0.10)",
};

// ---------- Copy ----------
// Single source of truth for every user-visible string AND image URL on the
// page. Edit copy here, never inline in JSX. Per LandingPage/CLAUDE.md: no
// hardcoded user-visible text in JSX. Image URLs live here too so this file
// stays a single editing surface for the one-pager.
const COPY = {
  pageTitle: "CombatDen — One Pager",
  brand: { name: "CombatDen" },
  hero: {
    headlinePre: "A member app that stops fighters ",
    headlineAccent: "from quitting.",
    headlinePost: "",
    tagline:
      "Works alongside your current software — no card migration required.",
  },
  engagement: {
    eyebrow: "Retention Booster",
    headline: "Engagement keeps members.",
    blurb:
      "Every part of the app is designed to keep members thinking about your gym.",
    moments: [
      {
        label: "Before class",
        copy: "Technique videos matched to their level.",
        img: "/assets/images/BJJClass.webp",
      },
      {
        label: "After class",
        copy: "Content based on the class type.",
        img: "/assets/images/Privates.webp",
      },
      {
        label: "Between classes",
        copy: "Rank tracking, streaks, and martial arts content.",
        img: "/assets/images/Boxing.jpg",
      },
    ],
  },
  loyalty: {
    eyebrow: "Loyalty Program",
    headline: "Make loyal members.",
    blurb:
      "We enable your gym to run a loyalty program that rewards consistency, keeps members longer, and grows your gym.",
    ptsLabel: "PTS",
    loop: [
      {
        label: "Attend class",
        desc: "Drives attendance.",
        img: "/assets/images/FriendPass.jpg",
      },
      {
        label: "Earn points",
        desc: "Promotes consistency.",
        pts: "+160",
      },
      {
        label: "Redeem rewards",
        desc: "Creates loyal members.",
        img: "/assets/images/ShirtReward.webp",
      },
    ],
  },
  branded: {
    eyebrow: "Truly Yours",
    headline: "App branded for your gym.",
    body: "The app ships with your logo, colors, and gym name baked in. When members open it, they see your brand.",
    img: "/assets/mockups/3d_branded.png",
    imgAlt: "Branded mobile app",
  },
  contact: {
    cta: "Book a 15-minute demo.",
    email: "jesse@combatden.net",
    phone: "832-871-2702",
    site: "combatden.net",
    siteCta: "combatden.net →",
  },
  glyphs: { arrow: "→", separator: " · " },
};

// ---------- Atoms ----------
function Wordmark({ color, size = 20 }) {
  return (
    <span
      style={{
        fontFamily: "Jura, Inter, system-ui, sans-serif",
        fontWeight: 700,
        fontSize: size,
        letterSpacing: "0.18em",
        color,
        textTransform: "uppercase",
      }}
    >
      {COPY.brand.name}
    </span>
  );
}

function Eyebrow({ children, color, size = 10 }) {
  return (
    <div
      style={{
        fontFamily: "Inter, sans-serif",
        fontSize: size,
        fontWeight: 700,
        letterSpacing: "0.22em",
        textTransform: "uppercase",
        color,
      }}
    >
      {children}
    </div>
  );
}

// 4-pointed orange sparkle, absolutely positioned around a parent.
// Used in the loyalty loop to mark the "earn points" slot without a frame.
function Sparkle({ size = 10, x = 0, y = 0, opacity = 1 }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      style={{
        position: "absolute",
        left: `calc(50% + ${x}px - ${size / 2}px)`,
        top: `calc(50% + ${y}px - ${size / 2}px)`,
        opacity,
      }}
    >
      <path
        d="M12 0 L14 10 L24 12 L14 14 L12 24 L10 14 L0 12 L10 10 Z"
        fill={P.orange}
      />
    </svg>
  );
}

function Section({ eyebrow, title, sectionH, children }) {
  return (
    <section style={{ height: sectionH, flex: "none", overflow: "hidden" }}>
      {eyebrow && (
        <div
          style={{
            display: "flex",
            alignItems: "baseline",
            justifyContent: "space-between",
            marginBottom: 6,
          }}
        >
          <Eyebrow color={P.orange}>{eyebrow}</Eyebrow>
          <div
            style={{
              flex: 1,
              marginLeft: 14,
              height: 1,
              background: P.hairline,
            }}
          />
        </div>
      )}
      {title && (
        <h2
          style={{
            margin: "0 0 8px",
            fontFamily: "Jura, sans-serif",
            fontSize: 20,
            fontWeight: 700,
            color: P.fg1,
            letterSpacing: "-0.01em",
            lineHeight: 1.05,
          }}
        >
          {title}
        </h2>
      )}
      {children}
    </section>
  );
}

// ---------- Page ----------
function OnePager() {
  return (
    <div
      style={{
        width: PAGE_W,
        height: PAGE_H,
        background: P.bg,
        color: P.fg1,
        position: "relative",
        overflow: "hidden",
        fontFamily: "Inter, system-ui, sans-serif",
        boxSizing: "border-box",
        padding: "48px 56px 64px",
      }}
    >
      {/* Glow accent */}
      <div
        style={{
          position: "absolute",
          right: -160,
          bottom: -160,
          width: 460,
          height: 460,
          background: `radial-gradient(circle, ${P.orange} 0%, transparent 60%)`,
          opacity: 0.08,
          pointerEvents: "none",
          zIndex: 0,
        }}
      />

      <div
        style={{
          position: "relative",
          zIndex: 1,
          display: "flex",
          flexDirection: "column",
          height: "100%",
          gap: 14,
        }}
      >
        {/* Top bar — wordmark only */}
        <div
          style={{
            height: 28,
            flex: "none",
            display: "flex",
            alignItems: "center",
          }}
        >
          <Wordmark color={P.orange} size={20} />
        </div>

        {/* Hero */}
        <div style={{ height: 96, flex: "none" }}>
          <h1
            style={{
              margin: 0,
              fontFamily: "Jura, sans-serif",
              fontSize: 32,
              fontWeight: 700,
              lineHeight: 1.05,
              letterSpacing: "-0.02em",
              color: P.fg1,
              maxWidth: 600,
              width: "800px",
            }}
          >
            {COPY.hero.headlinePre}
            <span style={{ color: P.orange }}>{COPY.hero.headlineAccent}</span>
            {COPY.hero.headlinePost}
          </h1>
          <p
            style={{
              margin: "6px 0 0",
              fontSize: 11.5,
              lineHeight: 1.45,
              color: P.fg2,
              maxWidth: 540,
            }}
          >
            {COPY.hero.tagline}
          </p>
        </div>

        {/* Engagement — variant B: text on left | numbered timeline on right */}
        <div style={{ height: 230, flex: "none" }}>
          <div
            style={{
              display: "grid",
              gridTemplateColumns: `${SECTION_TEXT_COL_W}px 1fr`,
              gap: SECTION_COL_GAP,
              alignItems: "center",
              height: "100%",
            }}
          >
            {/* LEFT — eyebrow + headline + blurb */}
            <div
              style={{
                display: "flex",
                flexDirection: "column",
                justifyContent: "center",
              }}
            >
              <Eyebrow color={P.orange}>{COPY.engagement.eyebrow}</Eyebrow>
              <h2
                style={{
                  margin: "8px 0 8px",
                  fontFamily: "Jura, sans-serif",
                  fontSize: 22,
                  fontWeight: 700,
                  color: P.fg1,
                  letterSpacing: "-0.01em",
                  lineHeight: 1.05,
                }}
              >
                {COPY.engagement.headline}
              </h2>
              <p
                style={{
                  margin: 0,
                  fontSize: 12,
                  lineHeight: 1.5,
                  color: P.fg2,
                }}
              >
                {COPY.engagement.blurb}
              </p>
            </div>

            {/* RIGHT — 01/02/03 timeline + per-moment thumbs */}
            <div style={{ position: "relative", paddingLeft: 4 }}>
              {/* Hairline tying the numbers together */}
              <div
                style={{
                  position: "absolute",
                  left: 16,
                  top: 14,
                  bottom: 14,
                  width: 1,
                  background: P.hairline,
                }}
              />
              <div
                style={{ display: "flex", flexDirection: "column", gap: 16 }}
              >
                {COPY.engagement.moments.map((m, i) => (
                  <div
                    key={m.label}
                    style={{
                      display: "grid",
                      gridTemplateColumns: "32px 1fr 88px",
                      gap: 14,
                      alignItems: "center",
                    }}
                  >
                    <div
                      style={{
                        fontFamily: "Jura, sans-serif",
                        fontSize: 15,
                        fontWeight: 700,
                        color: P.orange,
                        letterSpacing: "0.04em",
                        background: P.bg,
                        position: "relative",
                        zIndex: 1,
                        lineHeight: 1,
                      }}
                    >
                      {`0${i + 1}`}
                    </div>
                    <div>
                      <div
                        style={{ fontSize: 12, fontWeight: 700, color: P.fg1 }}
                      >
                        {m.label}
                      </div>
                      <div
                        style={{
                          marginTop: 2,
                          fontSize: 10.5,
                          lineHeight: 1.4,
                          color: P.fg2,
                        }}
                      >
                        {m.copy}
                      </div>
                    </div>
                    <div
                      style={{
                        position: "relative",
                        width: 88,
                        height: 50,
                        borderRadius: 6,
                        overflow: "hidden",
                        background: "#000",
                        border: `1.5px solid ${P.orange}`,
                        boxShadow: "0 4px 12px rgba(229,90,28,0.22)",
                      }}
                    >
                      <img
                        src={m.img}
                        alt={m.label}
                        style={{
                          position: "absolute",
                          inset: 0,
                          width: "100%",
                          height: "100%",
                          objectFit: "cover",
                          filter: "saturate(0.95) contrast(1.05)",
                        }}
                      />
                      <div
                        style={{
                          position: "absolute",
                          top: "50%",
                          left: "50%",
                          transform: "translate(-50%, -50%)",
                          width: 22,
                          height: 22,
                          borderRadius: "50%",
                          background: "rgba(255,255,255,0.95)",
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "center",
                          boxShadow: "0 2px 6px rgba(0,0,0,0.4)",
                        }}
                      >
                        <div
                          style={{
                            width: 0,
                            height: 0,
                            borderTop: "4px solid transparent",
                            borderBottom: "4px solid transparent",
                            borderLeft: `7px solid ${P.orange}`,
                            marginLeft: 2,
                          }}
                        />
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>

        {/* Loyalty — variant A: text LEFT | horizontal loop RIGHT */}
        <div style={{ height: 248, flex: "none" }}>
          <div style={{ height: 1, background: P.hairline, marginBottom: 6 }} />
          <div
            style={{
              display: "grid",
              gridTemplateColumns: `${SECTION_TEXT_COL_W}px 1fr`,
              gap: SECTION_COL_GAP,
              alignItems: "center",
              height: "calc(100% - 7px)",
            }}
          >
            {/* LEFT — eyebrow + headline + blurb */}
            <div
              style={{
                display: "flex",
                flexDirection: "column",
                justifyContent: "center",
              }}
            >
              <Eyebrow color={P.orange}>{COPY.loyalty.eyebrow}</Eyebrow>
              <h2
                style={{
                  margin: "8px 0 8px",
                  fontFamily: "Jura, sans-serif",
                  fontSize: 22,
                  fontWeight: 700,
                  color: P.fg1,
                  letterSpacing: "-0.01em",
                  lineHeight: 1.05,
                }}
              >
                {COPY.loyalty.headline}
              </h2>
              <p
                style={{
                  margin: 0,
                  fontSize: 12,
                  lineHeight: 1.5,
                  color: P.fg2,
                }}
              >
                {COPY.loyalty.blurb}
              </p>
            </div>

            {/* RIGHT — compact horizontal 3-step loop (64px circles) */}
            <div
              style={{
                display: "grid",
                gridTemplateColumns: "1fr 18px 1fr 18px 1fr",
                alignItems: "center",
                justifyItems: "center",
              }}
            >
              {COPY.loyalty.loop.map((s, i) => (
                <React.Fragment key={s.label}>
                  <div
                    style={{
                      display: "flex",
                      flexDirection: "column",
                      alignItems: "center",
                      gap: 6,
                    }}
                  >
                    <div
                      style={{
                        position: "relative",
                        width: 64,
                        height: 64,
                        flex: "none",
                      }}
                    >
                      {s.pts ? (
                        <React.Fragment>
                          <Sparkle size={7} x={-22} y={-15} opacity={0.85} />
                          <Sparkle size={5} x={20} y={-21} opacity={0.6} />
                          <Sparkle size={6} x={25} y={13} opacity={0.8} />
                          <Sparkle size={4} x={-21} y={18} opacity={0.55} />
                          <Sparkle size={3} x={0} y={-25} opacity={0.4} />
                          <div
                            style={{
                              position: "absolute",
                              inset: 0,
                              display: "flex",
                              flexDirection: "column",
                              alignItems: "center",
                              justifyContent: "center",
                              lineHeight: 1,
                            }}
                          >
                            <span
                              style={{
                                fontFamily: "'Jura', sans-serif",
                                fontWeight: 700,
                                fontSize: 21,
                                letterSpacing: "-0.02em",
                                color: P.orange,
                              }}
                            >
                              {s.pts}
                            </span>
                            <span
                              style={{
                                fontFamily: "'Jura', sans-serif",
                                fontWeight: 700,
                                fontSize: 7,
                                letterSpacing: "0.24em",
                                color: P.orange,
                                marginTop: 4,
                              }}
                            >
                              {COPY.loyalty.ptsLabel}
                            </span>
                          </div>
                        </React.Fragment>
                      ) : (
                        <div
                          style={{
                            position: "absolute",
                            inset: 0,
                            borderRadius: "50%",
                            overflow: "hidden",
                            background: P.bg,
                            border: `2px solid ${P.orange}`,
                            boxShadow: "0 3px 10px rgba(0,0,0,0.12)",
                          }}
                        >
                          <img
                            src={s.img}
                            alt={s.label}
                            style={{
                              position: "absolute",
                              inset: 0,
                              width: "100%",
                              height: "100%",
                              objectFit: "cover",
                              objectPosition: "center",
                              filter: "saturate(0.95) contrast(1.05)",
                            }}
                          />
                        </div>
                      )}
                    </div>
                    <div style={{ textAlign: "center" }}>
                      <div
                        style={{
                          fontSize: 11.5,
                          fontWeight: 700,
                          color: P.fg1,
                          letterSpacing: "-0.005em",
                        }}
                      >
                        {s.label}
                      </div>
                      <div
                        style={{
                          marginTop: 2,
                          fontSize: 10,
                          lineHeight: 1.35,
                          color: P.fg2,
                        }}
                      >
                        {s.desc}
                      </div>
                    </div>
                  </div>
                  {i < COPY.loyalty.loop.length - 1 && (
                    <div
                      style={{
                        color: P.orange,
                        fontSize: 18,
                        fontWeight: 700,
                        marginTop: -32,
                      }}
                    >
                      {COPY.glyphs.arrow}
                    </div>
                  )}
                </React.Fragment>
              ))}
            </div>
          </div>
        </div>

        {/* Branded */}
        <Section sectionH={200}>
          <div style={{ height: 1, background: P.hairline, marginBottom: 6 }} />
          <div
            style={{
              display: "grid",
              gridTemplateColumns: `${SECTION_TEXT_COL_W}px 1fr`,
              gap: SECTION_COL_GAP,
              alignItems: "center",
              height: "calc(100% - 7px)",
            }}
          >
            <div>
              <Eyebrow color={P.orange}>{COPY.branded.eyebrow}</Eyebrow>
              <h2
                style={{
                  margin: "6px 0 6px",
                  fontFamily: "Jura, sans-serif",
                  fontSize: 20,
                  fontWeight: 700,
                  color: P.fg1,
                  letterSpacing: "-0.01em",
                  lineHeight: 1.05,
                }}
              >
                {COPY.branded.headline}
              </h2>
              <p
                style={{
                  margin: 0,
                  fontSize: 12,
                  lineHeight: 1.55,
                  color: P.fg2,
                }}
              >
                {COPY.branded.body}
              </p>
            </div>
            <img
              src={COPY.branded.img}
              alt={COPY.branded.imgAlt}
              style={{
                width: "100%",
                height: 150,
                objectFit: "contain",
                objectPosition: "center",
                display: "block",
              }}
            />
          </div>
        </Section>

        {/* Footer / CTA */}
        <div
          style={{
            height: 70,
            flex: "none",
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            paddingTop: 12,
            borderTop: `1px solid ${P.hairline}`,
            boxSizing: "border-box",
          }}
        >
          <div>
            <div
              style={{
                fontFamily: "Jura, sans-serif",
                fontSize: 20,
                fontWeight: 700,
                color: P.fg1,
                letterSpacing: "-0.01em",
                lineHeight: 1.1,
              }}
            >
              {COPY.contact.cta}
            </div>
            <div style={{ marginTop: 5, fontSize: 11.5, color: P.fg2 }}>
              {COPY.contact.email}
              {COPY.glyphs.separator}
              {COPY.contact.phone}
            </div>
          </div>
          <div
            style={{
              padding: "11px 16px",
              background: P.orange,
              color: "#fff",
              fontWeight: 700,
              fontSize: 12,
              letterSpacing: "0.04em",
              borderRadius: 2,
            }}
          >
            {COPY.contact.siteCta}
          </div>
        </div>
      </div>
    </div>
  );
}

function App() {
  React.useEffect(() => {
    document.title = COPY.pageTitle;
  }, []);
  return (
    <div className="page-frame">
      <OnePager />
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
