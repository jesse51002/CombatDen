// CombatDen — Hi-Fi landing page (Manifesto direction)
// Hero uses Glow A (programmatic pulsing bottom gradient, stays large).

const { useEffect, useRef, useState } = React;

const C = {
  ink: "#121619",
  ink2: "#0B0E10",
  bone: "#F4F3EE",
  orange: "#FF6C2D",
  fg1: "#F4F3EE",
  fg2: "rgba(244,243,238,0.72)",
  fg3: "rgba(244,243,238,0.5)",
  fg4: "rgba(244,243,238,0.25)",
  divider: "rgba(244,243,238,0.15)",
  paper: "#F4F3EE",
  paperInk: "#121619",
  paperInk2: "#2E2E2E",
  paperInk3: "#6B6B6B",
  paperHairline: "rgba(18,22,25,0.12)",
};

// Shared typographic scale
const SECTION_EYEBROW_SIZE = 18; // Inter uppercase label above section headings

// ---------- rAF helper ----------
function useRaf(cb) {
  useEffect(() => {
    let running = true;
    const start = performance.now();
    function tick(now) {
      if (!running) return;
      cb((now - start) / 1000);
      requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
    return () => {
      running = false;
    };
  }, []);
}

// ---------- Shared Nav ----------
function Nav() {
  return (
    <div
      style={{
        position: "sticky",
        top: 0,
        zIndex: 50,
        height: 72,
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        padding: "0 48px",
        background: "rgba(18,22,25,0.82)",
        backdropFilter: "blur(16px)",
        WebkitBackdropFilter: "blur(16px)",
        borderBottom: `1px solid ${C.divider}`,
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 44 }}>
        <a href="#top" aria-label="CombatDen home" style={{ display: "inline-flex", alignItems: "center", lineHeight: 0 }}>
          <img src="assets/images/LogoTransparent.png" alt="CombatDen" style={{ height: 40, width: "auto", display: "block" }} />
        </a>
        <div
          style={{
            display: "flex",
            gap: 28,
            fontFamily: "Inter, sans-serif",
            fontSize: 14,
            color: "rgba(244,243,238,0.7)",
          }}
        >
          <a
            href="#how-it-works"
            style={{
              color: "inherit",
              textDecoration: "none",
              cursor: "pointer",
            }}
          >
            How it works
          </a>
          <a
            href="#why"
            style={{
              color: "inherit",
              textDecoration: "none",
              cursor: "pointer",
            }}
          >
            Why it matters
          </a>
          <a
            href="#faq"
            style={{
              color: "inherit",
              textDecoration: "none",
              cursor: "pointer",
            }}
          >
            FAQ
          </a>
        </div>
      </div>
      <a
        href="#book"
        style={{
          background: C.orange,
          color: C.bone,
          border: "none",
          padding: "12px 22px",
          borderRadius: 999,
          fontFamily: "Inter, sans-serif",
          fontWeight: 600,
          fontSize: 13,
          cursor: "pointer",
          letterSpacing: "0.01em",
          textDecoration: "none",
          display: "inline-block",
        }}
      >
        Book a demo →
      </a>
    </div>
  );
}

// ---------- Hero (Glow A — bottom gradient pulsating bigger/smaller, always large) ----------
function Hero() {
  const ref = useRef(null);
  useRaf((t) => {
    const el = ref.current;
    if (!el) return;
    // stays large; scale floats 1.1 → ~1.26; opacity 0.55 → 0.95
    const base =
      0.72 + 0.18 * Math.sin(t * 0.55) + 0.08 * Math.sin(t * 1.7 + 0.8);
    const scale = 1.1 + 0.12 * Math.sin(t * 0.55) + 0.04 * Math.sin(t * 2.3);
    el.style.opacity = String(Math.max(0.55, Math.min(0.95, base)));
    el.style.transform = `translate(-50%, -50%) scale(${scale.toFixed(3)})`;
  });
  return (
    <section
      style={{
        position: "relative",
        minHeight: 820,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        padding: "160px 64px 200px",
        textAlign: "center",
        overflow: "hidden",
        background: C.ink,
      }}
    >
      {/* Pulsing bottom glow */}
      <div
        ref={ref}
        style={{
          position: "absolute",
          left: "50%",
          top: "50%",
          width: 1900,
          height: 1500,
          transform: "translate(-50%, -50%) scale(1.1)",
          transformOrigin: "50% 50%",
          background: `radial-gradient(ellipse 50% 50% at 50% 50%, rgba(255,108,45,0.55) 0%, rgba(255,108,45,0.18) 40%, transparent 70%)`,
          filter: "blur(10px)",
          willChange: "transform, opacity",
          pointerEvents: "none",
        }}
      />
      {/* Content */}
      <div style={{ position: "relative", zIndex: 2 }}>
        <div
          style={{
            fontFamily: "'Jura', sans-serif",
            fontSize: SECTION_EYEBROW_SIZE,
            fontWeight: 700,
            letterSpacing: "0.22em",
            color: C.orange,
            textTransform: "uppercase",
          }}
        >
          For combat sports gyms
        </div>
        <h1
          style={{
            fontFamily: "Inter, sans-serif",
            fontWeight: 600,
            fontSize: 104,
            lineHeight: 1.0,
            letterSpacing: "-0.035em",
            color: C.bone,
            margin: "28px 0 0",
            maxWidth: 1200,
            textWrap: "balance",
          }}
        >
          A member app that stops
          <br />
          fighters from quitting.
        </h1>
        <p
          style={{
            fontFamily: "Inter, sans-serif",
            fontSize: 20,
            lineHeight: 1.5,
            color: C.fg2,
            maxWidth: 640,
            margin: "36px auto 0",
          }}
        >
          Works alongside your current software — no migration required.
        </p>
        <div
          style={{
            marginTop: 48,
            display: "flex",
            justifyContent: "center",
            gap: 14,
          }}
        >
          <a
            href="#book"
            style={{
              background: C.orange,
              color: C.bone,
              border: "none",
              padding: "18px 32px",
              borderRadius: 999,
              fontFamily: "Inter, sans-serif",
              fontWeight: 600,
              fontSize: 15,
              cursor: "pointer",
              textDecoration: "none",
              display: "inline-block",
            }}
          >
            Book a 15-minute demo
          </a>
        </div>
      </div>
    </section>
  );
}

// ---------- 02 · Problem (dark, giant stat) ----------
function Problem() {
  const sectionRef = useRef(null);
  const numberRef = useRef(null);
  const [progress, setProgress] = useState(0); // 0 → 1 as section scrolls through viewport
  const [centerOffset, setCenterOffset] = useState(0); // px to shift number to viewport center at its resting size

  useEffect(() => {
    function measure() {
      const el = numberRef.current;
      if (!el) return;
      // Temporarily clear transform to measure natural resting position
      const prev = el.style.transform;
      el.style.transform = "none";
      const rect = el.getBoundingClientRect();
      el.style.transform = prev;
      const naturalCenter = rect.left + rect.width / 2;
      const viewportCenter = window.innerWidth / 2;
      setCenterOffset(viewportCenter - naturalCenter);
    }
    function onScroll() {
      const el = sectionRef.current;
      if (!el) return;
      const rect = el.getBoundingClientRect();
      const vh = window.innerHeight;
      // Start only once the section is well into view; finish as it approaches the top.
      const start = vh * 0.4; // top near top of viewport → 0
      const end = vh * 0.05; // finish sooner — while section top is still near the top of viewport → 1
      const raw = (start - rect.top) / (start - end);
      const p = Math.max(0, Math.min(1, raw));
      setProgress(p);
    }
    measure();
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", () => {
      measure();
      onScroll();
    });
    return () => {
      window.removeEventListener("scroll", onScroll);
    };
  }, []);

  // ease-out cubic
  const eased = 1 - Math.pow(1 - progress, 3);
  const count = Math.round(50 * eased);
  const numberOpacity = 0.15 + 0.85 * eased;
  const numberBlur = (1 - eased) * 10;
  // Number starts centered + bigger, slides/shrinks to resting position as eased → 1.
  const numberShiftX = centerOffset * (1 - eased);
  const numberShiftY = (1 - eased) * -260;
  const numberScale = 1 + (1 - eased) * 0.6;
  const textOpacity = Math.max(0, (eased - 0.55) / 0.45);
  const textShift = (1 - Math.min(1, Math.max(0, (eased - 0.55) / 0.45))) * 16;

  return (
    <section
      ref={sectionRef}
      style={{
        background: C.ink,
        color: C.bone,
        padding: "280px 64px",
        borderTop: `1px solid ${C.divider}`,
        minHeight: "100vh",
        display: "flex",
        alignItems: "center",
      }}
    >
      <div style={{ maxWidth: 1200, margin: "0 auto" }}>
        <div
          style={{
            fontFamily: "Inter, sans-serif",
            fontSize: SECTION_EYEBROW_SIZE,
            fontWeight: 700,
            letterSpacing: "0.22em",
            color: C.orange,
            textTransform: "uppercase",
            marginBottom: 32,
            opacity: Math.min(1, eased * 2),
            transform: `translateY(${(1 - Math.min(1, eased * 2)) * 12}px)`,
          }}
        >
          The problem
        </div>
        <div
          style={{
            display: "flex",
            alignItems: "baseline",
            gap: 40,
            flexWrap: "wrap",
          }}
        >
          <span
            ref={numberRef}
            style={{
              fontFamily: "'Jura', sans-serif",
              fontWeight: 700,
              fontSize: 280,
              lineHeight: 0.85,
              letterSpacing: "-0.04em",
              color: C.bone,
              opacity: numberOpacity,
              filter: `blur(${numberBlur.toFixed(2)}px)`,
              display: "inline-block",
              transform: `translate(${numberShiftX.toFixed(1)}px, ${numberShiftY.toFixed(1)}px) scale(${numberScale.toFixed(3)})`,
              transformOrigin: "left center",
              willChange: "transform, opacity, filter",
            }}
          >
            {count}%
          </span>
          <h2
            style={{
              fontFamily: "Inter, sans-serif",
              fontWeight: 600,
              fontSize: 48,
              lineHeight: 1.05,
              letterSpacing: "-0.02em",
              maxWidth: 500,
              margin: 0,
              color: C.bone,
              opacity: textOpacity,
              transform: `translateY(${textShift.toFixed(2)}px)`,
              willChange: "transform, opacity",
            }}
          >
            of new members quit within 6 months.
          </h2>
        </div>
        <div
          style={{
            marginTop: 56,
            fontFamily: "Inter, sans-serif",
            fontSize: 14,
            color: C.fg3,
            letterSpacing: "0.04em",
            opacity: textOpacity * 0.9,
          }}
        >
          Source: IHRSA gym retention research
        </div>
      </div>
    </section>
  );
}

// ---------- 03 · Solution (paper, sentence completes on scroll) ----------
function Solution() {
  const sectionRef = useRef(null);
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    function onScroll() {
      const el = sectionRef.current;
      if (!el) return;
      const rect = el.getBoundingClientRect();
      const vh = window.innerHeight;
      // Drive progress off the section's center (where the content sits, since it's flex-centered).
      const center = rect.top + rect.height / 2;
      const start = vh * 1; // content center near bottom of viewport → 0
      const end = vh * 0.6; // content center just past middle → 1
      const raw = (start - center) / (start - end);
      setProgress(Math.max(0, Math.min(1, raw)));
    }
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    return () => {
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
    };
  }, []);

  const head = "Keeps your members engaged ";
  const tail = "between classes.";
  const eased = 1 - Math.pow(1 - progress, 3);
  const totalChars = head.length + tail.length;
  const charsShown = Math.round(totalChars * eased);

  // Blinking caret (inline, zero-width so layout never shifts).
  const Caret = () => (
    <span
      style={{
        display: "inline-block",
        width: 0,
        position: "relative",
        verticalAlign: "baseline",
      }}
    >
      <span
        style={{
          position: "absolute",
          left: 0,
          bottom: "-0.02em",
          width: "0.06em",
          height: "0.72em",
          background: C.orange,
          animation: "solution-caret 0.9s steps(2) infinite",
        }}
      />
    </span>
  );

  // Render text grouped by word (wrap-safe — words never split) with per-char
  // opacity and the caret inserted at the current typing position.
  const renderText = (text, offset, color) => {
    const tokens = text.split(/(\s+)/); // keep spaces as separate tokens
    let idx = offset;
    return tokens.map((tok, ti) => {
      if (tok.length === 0) return null;
      const tokStart = idx;
      idx += tok.length;
      if (/^\s+$/.test(tok)) {
        // Breakable whitespace between words. Caret can sit at this boundary.
        return (
          <React.Fragment key={`s${ti}`}>
            {tokStart === charsShown && <Caret />}
            <span style={{ opacity: tokStart < charsShown ? 1 : 0, color }}>
              {tok}
            </span>
          </React.Fragment>
        );
      }
      // Word: wrap in nowrap inline-block so it never splits; caret can sit between chars.
      return (
        <span
          key={`w${ti}`}
          style={{ display: "inline-block", whiteSpace: "nowrap", color }}
        >
          {Array.from(tok).map((ch, i) => {
            const cIdx = tokStart + i;
            return (
              <React.Fragment key={cIdx}>
                {cIdx === charsShown && <Caret />}
                <span
                  style={{
                    opacity: cIdx < charsShown ? 1 : 0,
                    transition: "opacity 80ms linear",
                  }}
                >
                  {ch}
                </span>
              </React.Fragment>
            );
          })}
        </span>
      );
    });
  };

  return (
    <section
      ref={sectionRef}
      style={{
        background: C.paper,
        color: C.paperInk,
        padding: "140px 64px",
        minHeight: "100vh",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        textAlign: "center",
      }}
    >
      <div style={{ maxWidth: 1100, margin: "0 auto" }}>
        <div
          style={{
            fontFamily: "Inter, sans-serif",
            fontSize: SECTION_EYEBROW_SIZE,
            fontWeight: 700,
            letterSpacing: "0.22em",
            color: C.orange,
            textTransform: "uppercase",
            marginBottom: 32,
          }}
        >
          Our solution
        </div>
        <h2
          style={{
            fontFamily: "Inter, sans-serif",
            fontWeight: 600,
            fontSize: 88,
            lineHeight: 0.98,
            letterSpacing: "-0.035em",
            margin: 0,
            maxWidth: 1000,
            textWrap: "balance",
          }}
        >
          {renderText(head, 0, "inherit")}
          {renderText(tail, head.length, C.orange)}
          {charsShown >= totalChars && <Caret />}
        </h2>
      </div>
      <style>{`
        @keyframes solution-caret { 50% { opacity: 0; } }
      `}</style>
    </section>
  );
}

// ---------- Phone mock component ----------
// Maps step variants to mockup images. `focus` (0..1) picks which vertical
// slice of the image to reveal inside the phone — 0 = top, 0.5 = middle, 1 = bottom.
const PHONE_IMAGES = {
  class: "assets/mockups/Class Screen.png",
  book: "assets/mockups/BeforeClass.png",
  after: "assets/mockups/AfterClass.png",
  between: "assets/mockups/BetweenClass.png",
};

function PhoneMock({
  variant = "book",
  focus = 0,
  width = 340,
  children,
  style = {},
}) {
  const imgSrc = PHONE_IMAGES[variant];
  const focusPct = Math.max(0, Math.min(1, focus)) * 100;
  return (
    <div
      style={{
        width: width,
        aspectRatio: "393/852",
        // Titanium-style frame: outer chrome edge → thin black bezel → screen.
        background: "#0a0c0e",
        borderRadius: 52,
        padding: 4, // outer chrome ring thickness
        backgroundImage:
          "linear-gradient(145deg, #d9dde2 0%, #8a8f96 35%, #e6e8ec 55%, #6f747b 75%, #c9ced5 100%)",
        boxShadow: [
          "0 30px 80px rgba(0,0,0,0.45)",
          "0 2px 0 rgba(255,255,255,0.35) inset",
          "0 -2px 0 rgba(0,0,0,0.35) inset",
        ].join(", "),
        position: "relative",
        ...style,
      }}
    >
      {/* Inner black bezel containing the screen */}
      <div
        style={{
          width: "100%",
          height: "100%",
          background: "#0a0c0e",
          borderRadius: 48,
          overflow: "hidden",
          position: "relative",
          boxShadow: "inset 0 0 0 1.5px rgba(0,0,0,0.9)",
        }}
      >
        {/* Dynamic Island */}
        <div
          style={{
            position: "absolute",
            top: 10,
            left: "50%",
            transform: "translateX(-50%)",
            width: 96,
            height: 28,
            background: "#000",
            borderRadius: 999,
            zIndex: 3,
            boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.04)",
          }}
        />
        {/* Side buttons */}
        <div
          style={{
            position: "absolute",
            left: -6,
            top: 110,
            width: 3,
            height: 28,
            background: "#8a8f96",
            borderRadius: 2,
          }}
        />
        <div
          style={{
            position: "absolute",
            left: -6,
            top: 160,
            width: 3,
            height: 56,
            background: "#8a8f96",
            borderRadius: 2,
          }}
        />
        <div
          style={{
            position: "absolute",
            left: -6,
            top: 224,
            width: 3,
            height: 56,
            background: "#8a8f96",
            borderRadius: 2,
          }}
        />
        <div
          style={{
            position: "absolute",
            right: -6,
            top: 180,
            width: 3,
            height: 86,
            background: "#8a8f96",
            borderRadius: 2,
          }}
        />
        {children ? (
          children
        ) : imgSrc ? (
          <img
            src={imgSrc}
            alt=""
            style={{
              width: "100%",
              height: "100%",
              objectFit: "cover",
              objectPosition: `50% ${focusPct}%`,
              display: "block",
            }}
          />
        ) : (
          <>
            <div
              style={{
                height: 44,
                padding: "0 24px",
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                fontFamily: "Inter, sans-serif",
                fontSize: 14,
                fontWeight: 600,
                color: C.bone,
              }}
            >
              <span>9:41</span>
              <span style={{ fontSize: 12 }}>●●● ▸</span>
            </div>
            <PhoneScreen variant={variant} />
          </>
        )}
      </div>
    </div>
  );
}

function PhoneScreen({ variant }) {
  if (variant === "book") {
    return (
      <div style={{ padding: "12px 20px 20px", color: C.bone }}>
        <div
          style={{
            fontFamily: "'Jura', sans-serif",
            fontSize: 11,
            letterSpacing: "0.2em",
            color: C.fg3,
            textTransform: "uppercase",
          }}
        >
          Tonight · 7:00 PM
        </div>
        <h3
          style={{
            fontFamily: "Inter, sans-serif",
            fontWeight: 700,
            fontSize: 26,
            margin: "8px 0 4px",
            letterSpacing: "-0.015em",
          }}
        >
          Muay Thai
        </h3>
        <div style={{ fontSize: 13, color: C.fg2 }}>
          Coach Ramon · 21 students
        </div>
        <button
          style={{
            marginTop: 18,
            width: "100%",
            padding: "14px",
            background: C.orange,
            color: C.bone,
            border: "none",
            borderRadius: 14,
            fontFamily: "Inter, sans-serif",
            fontWeight: 700,
            fontSize: 14,
            letterSpacing: "0.01em",
          }}
        >
          Book class
        </button>

        <div
          style={{
            marginTop: 24,
            padding: 16,
            background: "rgba(255,108,45,0.12)",
            border: `1px solid ${C.orange}`,
            borderRadius: 14,
          }}
        >
          <div
            style={{
              fontFamily: "'Jura', sans-serif",
              fontSize: 10,
              letterSpacing: "0.18em",
              color: C.orange,
              textTransform: "uppercase",
              fontWeight: 700,
            }}
          >
            Recommended for you
          </div>
          <div
            style={{
              fontFamily: "Inter, sans-serif",
              fontWeight: 600,
              fontSize: 15,
              marginTop: 6,
              lineHeight: 1.25,
            }}
          >
            Teep kick fundamentals
          </div>
          <div style={{ fontSize: 12, color: C.fg2, marginTop: 4 }}>
            3 min technique video · warm up for tonight
          </div>
          <div
            style={{
              marginTop: 12,
              aspectRatio: "16/9",
              borderRadius: 8,
              background:
                "linear-gradient(135deg, rgba(255,108,45,0.45), rgba(255,108,45,0.12))",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontSize: 22,
              color: C.bone,
            }}
          >
            ▶
          </div>
        </div>

        <div style={{ marginTop: 18 }}>
          <div
            style={{
              fontFamily: "Inter, sans-serif",
              fontWeight: 600,
              fontSize: 12,
              color: C.fg3,
              textTransform: "uppercase",
              letterSpacing: "0.12em",
            }}
          >
            This week
          </div>
          <div
            style={{
              marginTop: 10,
              display: "flex",
              flexDirection: "column",
              gap: 8,
            }}
          >
            {[
              ["Mon", "BJJ Fundamentals", "6:30p"],
              ["Wed", "Muay Thai", "7:00p"],
              ["Fri", "Open mat", "5:00p"],
            ].map(([d, n, t], i) => (
              <div
                key={i}
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  padding: "10px 12px",
                  background: "rgba(244,243,238,0.06)",
                  borderRadius: 10,
                  fontSize: 13,
                }}
              >
                <span style={{ color: C.fg2, width: 36 }}>{d}</span>
                <span style={{ flex: 1, color: C.bone }}>{n}</span>
                <span style={{ color: C.fg3 }}>{t}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    );
  }
  if (variant === "after") {
    return (
      <div style={{ padding: "12px 20px 20px", color: C.bone }}>
        <div
          style={{
            fontFamily: "'Jura', sans-serif",
            fontSize: 11,
            letterSpacing: "0.2em",
            color: C.fg3,
            textTransform: "uppercase",
          }}
        >
          Class finished · 8:02 PM
        </div>
        <h3
          style={{
            fontFamily: "Inter, sans-serif",
            fontWeight: 700,
            fontSize: 22,
            margin: "8px 0 14px",
            letterSpacing: "-0.01em",
          }}
        >
          Muay Thai · Coach Ramon
        </h3>

        <div
          style={{
            padding: 16,
            background: "rgba(244,243,238,0.06)",
            borderRadius: 14,
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <div
              style={{
                width: 32,
                height: 32,
                borderRadius: "50%",
                background: C.orange,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                fontSize: 14,
              }}
            >
              🎙
            </div>
            <div>
              <div style={{ fontSize: 13, fontWeight: 600 }}>
                Coach feedback
              </div>
              <div style={{ fontSize: 11, color: C.fg3 }}>
                Voice note · 0:34
              </div>
            </div>
          </div>
          {/* Waveform */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 2,
              height: 32,
              marginTop: 14,
            }}
          >
            {Array.from({ length: 42 }).map((_, i) => (
              <div
                key={i}
                style={{
                  flex: 1,
                  height: `${20 + Math.sin(i * 0.7) * 14 + Math.cos(i * 0.3) * 6}%`,
                  background: i < 18 ? C.orange : "rgba(244,243,238,0.3)",
                  borderRadius: 2,
                  minHeight: 3,
                }}
              />
            ))}
          </div>
        </div>

        <div
          style={{
            marginTop: 18,
            padding: 16,
            background: "rgba(255,108,45,0.1)",
            border: `1px solid rgba(255,108,45,0.35)`,
            borderRadius: 14,
          }}
        >
          <div
            style={{
              fontFamily: "'Jura', sans-serif",
              fontSize: 10,
              letterSpacing: "0.18em",
              color: C.orange,
              textTransform: "uppercase",
              fontWeight: 700,
            }}
          >
            Your next drill
          </div>
          <div
            style={{
              fontFamily: "Inter, sans-serif",
              fontWeight: 600,
              fontSize: 15,
              marginTop: 6,
              lineHeight: 1.3,
            }}
          >
            Keep your guard up when stepping out of the clinch
          </div>
          <div
            style={{
              fontSize: 12,
              color: C.fg2,
              marginTop: 6,
              lineHeight: 1.4,
            }}
          >
            Ramon flagged this in your voice note. We matched it to a 4-min
            drill.
          </div>
          <button
            style={{
              marginTop: 12,
              width: "100%",
              padding: "10px",
              background: C.orange,
              color: C.bone,
              border: "none",
              borderRadius: 10,
              fontFamily: "Inter, sans-serif",
              fontWeight: 600,
              fontSize: 13,
            }}
          >
            Watch 4-min drill
          </button>
        </div>

        <div
          style={{
            marginTop: 16,
            display: "grid",
            gridTemplateColumns: "1fr 1fr",
            gap: 8,
          }}
        >
          <div
            style={{
              padding: 12,
              background: "rgba(244,243,238,0.05)",
              borderRadius: 10,
            }}
          >
            <div
              style={{
                fontFamily: "'Jura', sans-serif",
                fontSize: 20,
                fontWeight: 700,
              }}
            >
              +50
            </div>
            <div
              style={{
                fontSize: 10,
                color: C.fg3,
                textTransform: "uppercase",
                letterSpacing: "0.1em",
              }}
            >
              Points earned
            </div>
          </div>
          <div
            style={{
              padding: 12,
              background: "rgba(244,243,238,0.05)",
              borderRadius: 10,
            }}
          >
            <div
              style={{
                fontFamily: "'Jura', sans-serif",
                fontSize: 20,
                fontWeight: 700,
              }}
            >
              14
            </div>
            <div
              style={{
                fontSize: 10,
                color: C.fg3,
                textTransform: "uppercase",
                letterSpacing: "0.1em",
              }}
            >
              Day streak
            </div>
          </div>
        </div>
      </div>
    );
  }
  if (variant === "between") {
    return (
      <div style={{ padding: "12px 20px 20px", color: C.bone }}>
        <div
          style={{
            fontFamily: "'Jura', sans-serif",
            fontSize: 11,
            letterSpacing: "0.2em",
            color: C.fg3,
            textTransform: "uppercase",
          }}
        >
          Your progress
        </div>
        <div
          style={{
            display: "flex",
            alignItems: "baseline",
            gap: 8,
            marginTop: 6,
          }}
        >
          <span
            style={{
              fontFamily: "'Jura', sans-serif",
              fontWeight: 700,
              fontSize: 54,
              lineHeight: 1,
              letterSpacing: "-0.03em",
            }}
          >
            47
          </span>
          <span style={{ fontSize: 13, color: C.fg2 }}>
            classes this quarter
          </span>
        </div>

        <div
          style={{
            marginTop: 20,
            padding: 14,
            background: "rgba(244,243,238,0.06)",
            borderRadius: 14,
          }}
        >
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              alignItems: "center",
            }}
          >
            <div
              style={{
                fontFamily: "'Jura', sans-serif",
                fontSize: 11,
                letterSpacing: "0.18em",
                color: C.fg3,
                textTransform: "uppercase",
                fontWeight: 700,
              }}
            >
              Blue belt · stripe 2
            </div>
            <div style={{ fontSize: 11, color: C.fg3 }}>63%</div>
          </div>
          <div
            style={{
              marginTop: 8,
              height: 6,
              borderRadius: 3,
              background: "rgba(244,243,238,0.12)",
              overflow: "hidden",
            }}
          >
            <div
              style={{ width: "63%", height: "100%", background: C.orange }}
            />
          </div>
        </div>

        <div
          style={{
            marginTop: 18,
            fontFamily: "Inter, sans-serif",
            fontWeight: 600,
            fontSize: 12,
            color: C.fg3,
            textTransform: "uppercase",
            letterSpacing: "0.12em",
          }}
        >
          Matched to your rank
        </div>
        <div
          style={{
            marginTop: 10,
            display: "flex",
            flexDirection: "column",
            gap: 10,
          }}
        >
          {[
            ["Half-guard sweep chains", "Blue belt · 6 min", true],
            ["Closed-guard breaks", "Blue belt · 4 min", false],
            ["Leg drag passing", "Blue belt · 8 min", false],
          ].map(([t, meta, featured], i) => (
            <div
              key={i}
              style={{
                display: "flex",
                gap: 10,
                alignItems: "center",
                padding: 10,
                background: featured
                  ? "rgba(255,108,45,0.12)"
                  : "rgba(244,243,238,0.05)",
                border: featured
                  ? `1px solid rgba(255,108,45,0.35)`
                  : "1px solid transparent",
                borderRadius: 10,
              }}
            >
              <div
                style={{
                  width: 56,
                  aspectRatio: "4/3",
                  borderRadius: 6,
                  background: featured
                    ? "linear-gradient(135deg, rgba(255,108,45,0.5), rgba(255,108,45,0.15))"
                    : "rgba(244,243,238,0.1)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  fontSize: 14,
                }}
              >
                ▶
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13, fontWeight: 600, lineHeight: 1.2 }}>
                  {t}
                </div>
                <div style={{ fontSize: 11, color: C.fg3, marginTop: 2 }}>
                  {meta}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    );
  }
  if (variant === "beginner") {
    return (
      <div style={{ padding: "12px 20px 20px", color: C.bone }}>
        <div
          style={{
            fontFamily: "'Jura', sans-serif",
            fontSize: 11,
            letterSpacing: "0.2em",
            color: C.fg3,
            textTransform: "uppercase",
          }}
        >
          Welcome · first class
        </div>
        <h3
          style={{
            fontFamily: "Inter, sans-serif",
            fontWeight: 700,
            fontSize: 22,
            margin: "8px 0 14px",
          }}
        >
          What to expect tonight
        </h3>
        <div
          style={{
            aspectRatio: "16/9",
            borderRadius: 12,
            background:
              "linear-gradient(135deg, rgba(255,108,45,0.35), rgba(255,108,45,0.1))",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: 28,
          }}
        >
          ▶
        </div>
        <div
          style={{
            marginTop: 16,
            display: "flex",
            flexDirection: "column",
            gap: 10,
          }}
        >
          {[
            ["👕", "What to wear", "Shorts + t-shirt is fine"],
            ["⏰", "Arrive 15 min early", "Coach will walk you through"],
            ["🥋", "No belt yet", "That's totally okay"],
          ].map(([ico, t, s], i) => (
            <div
              key={i}
              style={{
                display: "flex",
                gap: 12,
                alignItems: "center",
                padding: 12,
                background: "rgba(244,243,238,0.05)",
                borderRadius: 10,
              }}
            >
              <div
                style={{
                  width: 36,
                  height: 36,
                  borderRadius: 8,
                  background: "rgba(255,108,45,0.18)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  fontSize: 16,
                }}
              >
                {ico}
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13, fontWeight: 600 }}>{t}</div>
                <div style={{ fontSize: 11, color: C.fg3, marginTop: 2 }}>
                  {s}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    );
  }
  // advanced
  return (
    <div style={{ padding: "12px 20px 20px", color: C.bone }}>
      <div
        style={{
          fontFamily: "'Jura', sans-serif",
          fontSize: 11,
          letterSpacing: "0.2em",
          color: C.fg3,
          textTransform: "uppercase",
        }}
      >
        Drill matched to you
      </div>
      <h3
        style={{
          fontFamily: "Inter, sans-serif",
          fontWeight: 700,
          fontSize: 20,
          margin: "8px 0 4px",
          lineHeight: 1.2,
        }}
      >
        De la Riva → berimbolo entries
      </h3>
      <div style={{ fontSize: 12, color: C.fg2 }}>
        Based on Ramon's feedback last Thursday
      </div>

      <div
        style={{
          marginTop: 14,
          aspectRatio: "16/9",
          borderRadius: 12,
          background:
            "linear-gradient(135deg, rgba(255,108,45,0.4), rgba(255,108,45,0.12))",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          position: "relative",
        }}
      >
        <div style={{ fontSize: 28 }}>▶</div>
        <div
          style={{
            position: "absolute",
            bottom: 8,
            right: 10,
            fontFamily: "'Jura', sans-serif",
            fontSize: 11,
            color: C.bone,
            fontWeight: 700,
            letterSpacing: "0.05em",
          }}
        >
          6:42
        </div>
      </div>

      <div
        style={{
          marginTop: 16,
          padding: 12,
          background: "rgba(244,243,238,0.06)",
          borderRadius: 10,
        }}
      >
        <div
          style={{
            fontFamily: "'Jura', sans-serif",
            fontSize: 10,
            letterSpacing: "0.18em",
            color: C.orange,
            fontWeight: 700,
            textTransform: "uppercase",
          }}
        >
          Why this drill
        </div>
        <div
          style={{ fontSize: 12, color: C.fg2, marginTop: 6, lineHeight: 1.4 }}
        >
          You've been stalling at DLR guard against stronger passers. This
          addresses your weak off-hand grip.
        </div>
      </div>

      <div style={{ marginTop: 14, display: "flex", gap: 8 }}>
        <div
          style={{
            flex: 1,
            padding: 10,
            background: "rgba(244,243,238,0.05)",
            borderRadius: 10,
            textAlign: "center",
          }}
        >
          <div
            style={{
              fontFamily: "'Jura', sans-serif",
              fontSize: 18,
              fontWeight: 700,
            }}
          >
            142
          </div>
          <div
            style={{
              fontSize: 10,
              color: C.fg3,
              textTransform: "uppercase",
              letterSpacing: "0.1em",
            }}
          >
            Classes
          </div>
        </div>
        <div
          style={{
            flex: 1,
            padding: 10,
            background: "rgba(244,243,238,0.05)",
            borderRadius: 10,
            textAlign: "center",
          }}
        >
          <div
            style={{
              fontFamily: "'Jura', sans-serif",
              fontSize: 18,
              fontWeight: 700,
              color: C.orange,
            }}
          >
            🟤
          </div>
          <div
            style={{
              fontSize: 10,
              color: C.fg3,
              textTransform: "uppercase",
              letterSpacing: "0.1em",
            }}
          >
            Brown · 2 stripes
          </div>
        </div>
      </div>
    </div>
  );
}

// ---------- 04 · How It Works (sticky phone, text scrolls on the right) ----------
function HowItWorks() {
  const steps = [
    {
      n: "01",
      title: "Book a class.",
      copy: "Content based on the class and skill level.",
      variant: "book",
      focus: 0,
      images: [
        { variant: "class", focus: 0 },
        { variant: "book", focus: 0 },
      ],
    },
    {
      n: "02",
      title: "After class.",
      copy: "Coach feedback and educational video.",
      disclaimer: "Takes 5 minute to give feedback to a class.",
      variant: "after",
      focus: 0,
    },
    {
      n: "03",
      title: "Between classes.",
      copy: "Visual progress and videos to improve.",
      variant: "between",
      focus: 0,
    },
  ];

  const [active, setActive] = useState(0);
  const titleRef = useRef(null);
  const [phoneWidth, setPhoneWidth] = useState(320);
  const [titleHeight, setTitleHeight] = useState(180);
  useEffect(() => {
    function update() {
      const NAV = 72;
      const titleH = titleRef.current ? titleRef.current.offsetHeight : 160;
      setTitleHeight(titleH);
      // Phone sits below title (paddingTop=titleH). Available height = sticky - title - small bottom margin.
      const available = window.innerHeight - NAV - titleH - 48;
      const w = Math.min(340, (available * 393) / 852);
      setPhoneWidth(Math.max(200, Math.round(w)));
    }
    update();
    window.addEventListener("resize", update);
    const raf = requestAnimationFrame(update);
    return () => {
      window.removeEventListener("resize", update);
      cancelAnimationFrame(raf);
    };
  }, []);
  const [opacities, setOpacities] = useState(() =>
    steps.map((_, i) => (i === 0 ? 1 : 0)),
  );
  const stepRefs = [useRef(null), useRef(null), useRef(null)];

  useEffect(() => {
    function onScroll() {
      const vh = window.innerHeight;
      const vc = vh / 2;
      const next = stepRefs.map((ref, i) => {
        const el = ref.current;
        if (!el) return 0;
        const r = el.getBoundingClientRect();
        const c = r.top + r.height / 2;
        const dist = Math.abs(c - vc);
        // Step 0 gets a wider fade window so it stays fully visible longer before fading out.
        const window = i === 0 ? vh * 0.8 : vh * 0.5;
        const t = Math.max(0, 1 - dist / window);
        const fade = Math.pow(t, 0.35);
        return fade;
      });
      setOpacities(next);
      // Prefer the step currently most in view; if none are in view (scrolled past),
      // stick to the last step whose center has already crossed above viewport center.
      let best = 0;
      let bestVal = next[0];
      for (let i = 1; i < next.length; i++) {
        if (next[i] > bestVal) {
          best = i;
          bestVal = next[i];
        }
      }
      if (bestVal <= 0.001) {
        let passed = -1;
        for (let i = 0; i < stepRefs.length; i++) {
          const el = stepRefs[i].current;
          if (!el) continue;
          const r = el.getBoundingClientRect();
          if (r.top + r.height / 2 < vc) passed = i;
        }
        if (passed >= 0) best = passed;
      }
      setActive(best);
    }
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    return () => {
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
    };
  }, []);

  return (
    <section
      id="how-it-works"
      style={{
        background: C.ink,
        color: C.bone,
        padding: "120px 64px 180px",
        scrollMarginTop: 72,
      }}
    >
      <div style={{ maxWidth: 1280, margin: "0 auto", position: "relative" }}>
        {/* Single sticky group: title absolutely positioned at top so it doesn't steal height from the phone */}
        <div
          style={{
            position: "sticky",
            top: 72,
            height: "calc(100vh - 72px)",
          }}
        >
          {/* Title overlaid at top — doesn't occupy layout height, so phone gets full sticky height */}
          <div
            ref={titleRef}
            style={{
              position: "absolute",
              top: 0,
              left: 0,
              right: 0,
              padding: "48px 0 32px",
              zIndex: 2,
            }}
          >
            <div
              style={{
                fontFamily: "Inter, sans-serif",
                fontSize: SECTION_EYEBROW_SIZE,
                fontWeight: 700,
                letterSpacing: "0.22em",
                color: C.orange,
                textTransform: "uppercase",
                marginBottom: 16,
              }}
            >
              How it works
            </div>
            <h2
              style={{
                fontFamily: "Inter, sans-serif",
                fontWeight: 600,
                fontSize: 56,
                lineHeight: 1,
                letterSpacing: "-0.03em",
                margin: 0,
                maxWidth: 900,
                textWrap: "balance",
                color: C.bone,
              }}
            >
              Make every interaction engaging.
            </h2>
          </div>
          {/* Phone + right spacer, occupying full sticky with paddingTop reserving space for the title */}
          <div
            style={{
              height: "100%",
              paddingTop: titleHeight,
              display: "grid",
              gridTemplateColumns: "1fr 1fr",
              gridTemplateRows: "1fr",
              gap: 100,
              minHeight: 0,
              boxSizing: "border-box",
            }}
          >
            <div
              style={{
                position: "relative",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                minHeight: 0,
                minWidth: 0,
                overflow: "hidden",
              }}
            >
              <div
                style={{
                  position: "relative",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                {/* All step phones rendered stacked — active one fades in, others out */}
                {steps.map((s, i) => {
                  const isActive = i === active;
                  const common = {
                    position: i === 0 ? "relative" : "absolute",
                    inset: i === 0 ? undefined : 0,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    opacity: isActive ? 1 : 0,
                    transition: "opacity 420ms ease",
                    pointerEvents: isActive ? "auto" : "none",
                  };
                  return (
                    <div key={i} style={common}>
                      {s.images ? (
                        <div
                          style={{
                            display: "flex",
                            alignItems: "center",
                            gap: 18,
                          }}
                        >
                          {s.images.map((img, j) => (
                            <React.Fragment key={j}>
                              <PhoneMock
                                variant={img.variant}
                                focus={img.focus ?? 0}
                                width={Math.round((phoneWidth * 230) / 340)}
                              />
                              {j < s.images.length - 1 && (
                                <div
                                  style={{
                                    color: C.orange,
                                    fontSize: 40,
                                    fontWeight: 600,
                                    lineHeight: 1,
                                    userSelect: "none",
                                  }}
                                >
                                  →
                                </div>
                              )}
                            </React.Fragment>
                          ))}
                        </div>
                      ) : (
                        <PhoneMock
                          variant={s.variant}
                          focus={s.focus}
                          width={phoneWidth}
                        />
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
            <div />{" "}
            {/* reserved right half; steps overlay here via negative margin */}
          </div>
        </div>

        {/* Scrolling step blocks — sibling overlaid on right half */}
        <div
          style={{
            marginTop: "-100vh",
            marginLeft: "50%",
            paddingLeft: 50,
            paddingTop: "50vh",
            paddingBottom: "30vh",
            position: "relative",
            display: "flex",
            flexDirection: "column",
          }}
        >
          {steps.map((s, i) => (
            <div
              key={i}
              ref={stepRefs[i]}
              data-step={i}
              style={{
                minHeight: "80vh",
                display: "flex",
                flexDirection: "column",
                justifyContent: "center",
                opacity: opacities[i],
                transition: "opacity 120ms linear",
              }}
            >
              <div
                style={{
                  fontFamily: "'Jura', sans-serif",
                  fontSize: 72,
                  fontWeight: 700,
                  color: active === i ? C.orange : "rgba(244,243,238,0.35)",
                  letterSpacing: "-0.02em",
                  lineHeight: 1,
                  transition: "color 240ms",
                }}
              >
                {s.n}
              </div>
              <h3
                style={{
                  fontFamily: "Inter, sans-serif",
                  fontWeight: 600,
                  fontSize: 44,
                  margin: "16px 0 0",
                  letterSpacing: "-0.02em",
                  color: active === i ? C.bone : "rgba(244,243,238,0.45)",
                  transition: "color 240ms",
                }}
              >
                {s.title}
              </h3>
              <p
                style={{
                  fontFamily: "Inter, sans-serif",
                  fontSize: 18,
                  lineHeight: 1.5,
                  color: C.fg2,
                  margin: "20px 0 0",
                  maxWidth: 480,
                }}
              >
                {s.copy}
              </p>
              {s.disclaimer && (
                <p
                  style={{
                    fontFamily: "Inter, sans-serif",
                    fontStyle: "italic",
                    fontSize: 15,
                    lineHeight: 1.5,
                    color: C.fg3,
                    margin: "12px 0 0",
                    maxWidth: 480,
                  }}
                >
                  {s.disclaimer}
                </p>
              )}
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

// ---------- 06 · Profitable Loyalty (paper) ----------
function Loyalty() {
  return (
    <>
      <section
        style={{
          background: C.paper,
          color: C.paperInk,
          padding: "160px 64px",
        }}
      >
        <div style={{ maxWidth: 1280, margin: "0 auto" }}>
          <LoopSequence />
        </div>
      </section>

      <RewardsMarketing />
    </>
  );
}

function RewardCard({ body, src, borderProgress = 0 }) {
  const [hover, setHover] = useState(false);
  const cardRef = useRef(null);
  const [dims, setDims] = useState({ w: 0, h: 0 });
  useEffect(() => {
    const el = cardRef.current;
    if (!el) return;
    const update = () => setDims({ w: el.offsetWidth, h: el.offsetHeight });
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  const radius = 24;
  return (
    <div
      ref={cardRef}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        position: "relative",
        borderRadius: radius,
        // overflow kept visible so the SVG border overlay isn't clipped by the image;
        // the image has its own overflow: hidden container inside.
        overflow: "visible",
        background: "rgba(244,243,238,0.04)",
        border: `1px solid ${C.divider}`,
        transition: "transform 280ms ease, box-shadow 280ms ease",
        transform: hover ? "translateY(-6px)" : "translateY(0)",
        boxShadow: hover
          ? "0 24px 60px rgba(0,0,0,0.35)"
          : "0 8px 24px rgba(0,0,0,0.18)",
        cursor: "default",
      }}
    >
      {/* Hero image — taller, square-ish, dominant */}
      <div
        style={{
          position: "relative",
          aspectRatio: "1/1",
          overflow: "hidden",
          background: "#0a0c0e",
          borderTopLeftRadius: radius - 1,
          borderTopRightRadius: radius - 1,
        }}
      >
        <img
          src={src}
          alt=""
          style={{
            width: "100%",
            height: "100%",
            objectFit: "cover",
            display: "block",
            transform: hover ? "scale(1.06)" : "scale(1)",
            transition:
              "transform 500ms cubic-bezier(0.2, 0.7, 0.2, 1), filter 280ms ease",
            filter: hover ? "saturate(1.05)" : "saturate(0.95)",
          }}
        />
        {/* Soft top-shadow for legibility */}
        <div
          style={{
            position: "absolute",
            inset: 0,
            background:
              "linear-gradient(180deg, rgba(0,0,0,0.18) 0%, transparent 30%, transparent 70%, rgba(0,0,0,0.35) 100%)",
            pointerEvents: "none",
          }}
        />
        {/* Orange glow wash — stronger on hover */}
        <div
          style={{
            position: "absolute",
            inset: 0,
            background:
              "radial-gradient(ellipse 80% 60% at 50% 115%, rgba(255,108,45,0.5) 0%, transparent 60%)",
            opacity: hover ? 1 : 0.5,
            transition: "opacity 320ms ease",
            pointerEvents: "none",
          }}
        />
      </div>

      {/* Subtitle */}
      <div style={{ padding: "32px 32px 36px", textAlign: "center" }}>
        <p
          style={{
            fontFamily: "Inter, sans-serif",
            fontWeight: 500,
            fontSize: 19,
            lineHeight: 1.4,
            color: C.bone,
            margin: 0,
            letterSpacing: "-0.01em",
            textWrap: "balance",
          }}
        >
          {body}
        </p>
      </div>

      {/* Scroll-drawn orange border (rendered last so it paints on top of image & text) */}
      {dims.w > 0 && (
        <svg
          width={dims.w}
          height={dims.h}
          style={{
            position: "absolute",
            inset: 0,
            pointerEvents: "none",
            zIndex: 10,
          }}
        >
          <rect
            x="1"
            y="1"
            width={dims.w - 2}
            height={dims.h - 2}
            rx={radius - 1}
            ry={radius - 1}
            fill="none"
            stroke={C.orange}
            strokeWidth="2"
            pathLength="1"
            strokeDasharray="1 1"
            strokeDashoffset={1 - borderProgress}
            style={{ transition: "stroke-dashoffset 120ms linear" }}
          />
        </svg>
      )}
    </div>
  );
}

function RewardsMarketing() {
  const highlight = (text) => (
    <span style={{ color: C.orange, fontWeight: 600 }}>{text}</span>
  );
  const items = [
    {
      body: (
        <>Friend passes are {highlight("free leads")} members bring for you.</>
      ),
      src: "assets/images/FriendPass.webp",
    },
    {
      body: <>Branded shirts are cheap and make {highlight("walking ads")}.</>,
      src: "assets/images/FreeBranding.png",
    },
    {
      body: (
        <>
          Discounted privates convert people to{" "}
          {highlight("full-price privates")}.
        </>
      ),
      src: "assets/images/Privates.webp",
    },
  ];
  const sectionRef = useRef(null);
  const [progress, setProgress] = useState(0);
  useEffect(() => {
    function onScroll() {
      const el = sectionRef.current;
      if (!el) return;
      const rect = el.getBoundingClientRect();
      const vh = window.innerHeight;
      // Progress driven by the section's center crossing the viewport center.
      const center = rect.top + rect.height / 2;
      const start = vh; // center at bottom of viewport → 0
      const end = vh / 2; // center at middle of viewport → 1
      const raw = (start - center) / (start - end);
      setProgress(Math.max(0, Math.min(1, raw)));
    }
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    return () => {
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
    };
  }, []);

  return (
    <section
      ref={sectionRef}
      style={{
        background: C.ink,
        color: C.bone,
        padding: "160px 64px",
        minHeight: "100vh",
      }}
    >
      <div style={{ maxWidth: 1280, margin: "0 auto", width: "100%" }}>
        <div
          style={{
            fontFamily: "Inter, sans-serif",
            fontSize: SECTION_EYEBROW_SIZE,
            fontWeight: 700,
            letterSpacing: "0.22em",
            color: C.orange,
            textTransform: "uppercase",
            marginBottom: 24,
          }}
        >
          Grows your gym
        </div>
        <h2
          style={{
            fontFamily: "Inter, sans-serif",
            fontWeight: 600,
            fontSize: 64,
            lineHeight: 1,
            letterSpacing: "-0.03em",
            margin: "0 0 140px",
            maxWidth: 900,
            textWrap: "balance",
            color: C.bone,
          }}
        >
          Rewards double as marketing.
        </h2>

        <div
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(3, 1fr)",
            gap: 24,
          }}
        >
          {items.map((it, i) => (
            <RewardCard key={i} {...it} borderProgress={progress} />
          ))}
        </div>
        <p
          style={{
            marginTop: 32,
            fontFamily: "Inter, sans-serif",
            fontSize: 14,
            fontStyle: "italic",
            color: C.fg3,
            textAlign: "center",
          }}
        >
          Fully customizable — offer whatever rewards fit your gym.
        </p>
      </div>
    </section>
  );
}

// Scroll-driven loop sequence: pins while scrolling, line fills left→right,
// and each circle scales up as the active point passes over it.
function LoopSequence() {
  const items = [
    {
      img: "assets/images/BJJClass.webp",
      label: "Attends class",
      desc: "Train Hard.",
    },
    {
      text: "+160",
      label: "Earn points",
      desc: "Promotes class consistency.",
    },
    {
      img: "assets/images/ShirtReward.webp",
      label: "Redeem rewards",
      desc: "Creates loyal and profitable members",
    },
  ];
  const wrapRef = useRef(null);
  const [progress, setProgress] = useState(0); // 0..1 across the pinned scroll range

  useEffect(() => {
    function onScroll() {
      const el = wrapRef.current;
      if (!el) return;
      const rect = el.getBoundingClientRect();
      const vh = window.innerHeight;
      const total = rect.height - vh;
      const scrolled = Math.max(0, Math.min(total, -rect.top));
      setProgress(total > 0 ? scrolled / total : 0);
    }
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    return () => {
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
    };
  }, []);

  const n = items.length;
  // progress points for each circle (evenly spread with padding at the ends)
  const stops = items.map((_, i) => (i + 0.5) / n);

  return (
    <div ref={wrapRef} style={{ height: `${n * 100}vh`, position: "relative" }}>
      <div
        style={{
          position: "sticky",
          top: 0,
          height: "100vh",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <div
          style={{
            width: "100%",
            maxWidth: 1100,
            position: "relative",
            padding: "0 40px",
          }}
        >
          {/* Title — first in the group, disclaimer + sequence follow */}
          <div style={{ textAlign: "center", marginBottom: 40 }}>
            <div
              style={{
                fontFamily: "Inter, sans-serif",
                fontSize: SECTION_EYEBROW_SIZE,
                fontWeight: 700,
                letterSpacing: "0.22em",
                color: C.orange,
                textTransform: "uppercase",
                marginBottom: 16,
              }}
            >
              Profitable loyalty
            </div>
            <h2
              style={{
                fontFamily: "Inter, sans-serif",
                fontWeight: 600,
                fontSize: 48,
                lineHeight: 1.02,
                letterSpacing: "-0.03em",
                margin: "0 auto",
                maxWidth: 800,
                textWrap: "balance",
              }}
            >
              Rewards keep members training.
            </h2>
          </div>
          {/* Disclaimer above the sequence */}
          <p
            style={{
              margin: "0 0 56px",
              fontFamily: "Inter, sans-serif",
              fontSize: 15,
              fontStyle: "italic",
              color: C.paperInk3,
              textAlign: "center",
            }}
          >
            Points-per-class and reward tiers are fully configurable by the gym.
          </p>

          <div style={{ position: "relative" }}>
            {/* Connecting line (track + filled) — centered on circle row (80px = half of 160px circle) */}
            <div
              style={{
                position: "absolute",
                left: 0,
                right: 0,
                top: 80,
                transform: "translateY(-50%)",
                height: 3,
                background: C.paperHairline,
                borderRadius: 999,
              }}
            />
            <div
              style={{
                position: "absolute",
                left: 0,
                top: 80,
                transform: "translateY(-50%)",
                width: `${progress * 100}%`,
                height: 3,
                background: C.orange,
                borderRadius: 999,
                transition: "width 80ms linear",
              }}
            />

            <div
              style={{
                display: "grid",
                gridTemplateColumns: `repeat(${n}, 1fr)`,
                alignItems: "start",
                position: "relative",
              }}
            >
              {items.map((it, i) => {
                // bell-shaped scale peaking when progress === stops[i]
                const dist = Math.abs(progress - stops[i]);
                const bump = Math.max(0, 1 - dist / (1 / n));
                const scale = 1 + 1.4 * Math.pow(bump, 1.2);
                const reached = progress >= stops[i] - 0.02;
                return (
                  <div
                    key={i}
                    style={{
                      textAlign: "center",
                      transform: `scale(${scale.toFixed(3)})`,
                      transformOrigin: "50% 30%",
                      transition: "transform 120ms linear",
                    }}
                  >
                    <div
                      style={{
                        position: "relative",
                        width: 160,
                        height: 160,
                        margin: "0 auto",
                        borderRadius: "50%",
                        background: it.img ? C.ink : "#E8E6DF",
                        border: `4px solid ${reached ? C.orange : C.paperHairline}`,
                        overflow: "hidden",
                        transition:
                          "border-color 180ms ease, box-shadow 180ms ease",
                        boxShadow: reached
                          ? "0 16px 44px rgba(255,108,45,0.28)"
                          : "none",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                      }}
                    >
                      {!it.img && (
                        <div
                          style={{
                            position: "absolute",
                            inset: 0,
                            background:
                              "radial-gradient(circle at 35% 30%, #FFA87A 0%, #FF6C2D 45%, #D94F14 100%)",
                            boxShadow: [
                              "inset 0 -6px 14px rgba(0,0,0,0.22)",
                              "inset 0 6px 14px rgba(255,255,255,0.28)",
                            ].join(", "),
                            opacity: bump,
                            transition: "opacity 120ms linear",
                            pointerEvents: "none",
                          }}
                        />
                      )}
                      {it.img ? (
                        <img
                          src={it.img}
                          alt=""
                          style={{
                            width: "100%",
                            height: "100%",
                            objectFit: "cover",
                            display: "block",
                          }}
                        />
                      ) : (
                        <div
                          style={{
                            position: "relative",
                            zIndex: 1,
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
                              fontSize: 54,
                              letterSpacing: "-0.02em",
                              // muted dark off-focus → white on-focus
                              color: bump > 0.5 ? C.bone : C.paperInk2,
                              textShadow:
                                bump > 0.5
                                  ? "0 2px 6px rgba(0,0,0,0.18)"
                                  : "none",
                              transition:
                                "color 180ms ease, text-shadow 180ms ease",
                            }}
                          >
                            {it.text}
                          </span>
                          <span
                            style={{
                              fontFamily: "'Jura', sans-serif",
                              fontWeight: 700,
                              fontSize: 12,
                              letterSpacing: "0.24em",
                              color:
                                bump > 0.5
                                  ? "rgba(244,243,238,0.92)"
                                  : C.paperInk3,
                              marginTop: 8,
                              transition: "color 180ms ease",
                            }}
                          >
                            PTS
                          </span>
                        </div>
                      )}
                    </div>
                    <div
                      style={{
                        fontFamily: "'Jura', sans-serif",
                        fontSize: SECTION_EYEBROW_SIZE,
                        fontWeight: 700,
                        letterSpacing: "0.14em",
                        color: reached ? C.orange : C.paperInk3,
                        marginTop: 36,
                        textTransform: "uppercase",
                        transition: "color 180ms ease",
                      }}
                    >
                      {it.label}
                    </div>
                    <div
                      style={{
                        fontFamily: "Inter, sans-serif",
                        fontSize: 14,
                        color: C.paperInk2,
                        marginTop: 8,
                      }}
                    >
                      {it.desc}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function LoopStep({ icon, label, desc }) {
  return (
    <div style={{ textAlign: "center", position: "relative", zIndex: 1 }}>
      <div
        style={{
          width: 128,
          height: 128,
          margin: "0 auto",
          borderRadius: "50%",
          background: "rgba(18,22,25,0.04)",
          border: `1px solid ${C.paperHairline}`,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontSize: 42,
          color: C.orange,
        }}
      >
        {icon}
      </div>
      <div
        style={{
          fontFamily: "'Jura', sans-serif",
          fontSize: SECTION_EYEBROW_SIZE,
          fontWeight: 700,
          letterSpacing: "0.14em",
          color: C.orange,
          marginTop: 20,
          textTransform: "uppercase",
        }}
      >
        {label}
      </div>
      <div
        style={{
          fontFamily: "Inter, sans-serif",
          fontSize: 14,
          color: C.paperInk2,
          marginTop: 8,
        }}
      >
        {desc}
      </div>
    </div>
  );
}
function LoopArrow() {
  return (
    <div
      style={{
        fontFamily: "'Jura', sans-serif",
        fontSize: 42,
        fontWeight: 700,
        color: C.orange,
        textAlign: "center",
        position: "relative",
        zIndex: 1,
      }}
    >
      →
    </div>
  );
}

// ---------- 07 · Why It Matters (dark, two stats) ----------
function WhyItMatters() {
  const sectionRef = useRef(null);
  const [progress, setProgress] = useState(0);
  useEffect(() => {
    function onScroll() {
      const el = sectionRef.current;
      if (!el) return;
      const rect = el.getBoundingClientRect();
      const vh = window.innerHeight;
      // Drive progress off the section's center vs viewport center (not its top vs bottom).
      const center = rect.top + rect.height / 2;
      const start = vh * 0.9; // center near bottom of viewport → 0
      const end = vh * 0.5; // center at middle of viewport → 1
      const raw = (start - center) / (start - end);
      setProgress(Math.max(0, Math.min(1, raw)));
    }
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    return () => {
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
    };
  }, []);
  const eased = 1 - Math.pow(1 - progress, 3);
  const num1 = (7 * eased).toFixed(1).replace(/\.0$/, "");
  const num2 = (9 * eased).toFixed(1).replace(/\.0$/, "");
  return (
    <section
      id="why"
      ref={sectionRef}
      style={{
        background: C.paper,
        color: C.paperInk,
        padding: "120px 64px",
        minHeight: "100vh",
        display: "flex",
        alignItems: "center",
        scrollMarginTop: 72,
      }}
    >
      <div
        style={{
          maxWidth: 1280,
          margin: "0 auto",
          width: "100%",
          textAlign: "center",
        }}
      >
        <h2
          style={{
            fontFamily: "Inter, sans-serif",
            fontWeight: 700,
            fontSize: 80,
            lineHeight: 1,
            letterSpacing: "-0.02em",
            margin: "0 auto 80px",
            maxWidth: 1100,
            textWrap: "balance",
            color: C.paperInk,
            textTransform: "uppercase",
          }}
        >
          Why it matters
        </h2>
        <div
          style={{
            display: "grid",
            gridTemplateColumns: "1fr 1fr",
            gap: 80,
            marginTop: 40,
          }}
        >
          {[
            [`${num1}×`, "cheaper to keep a member than acquire a new one."],
            [
              `$${num2}k`,
              "more a year from retaining 5% more members in a 100-member gym.",
            ],
          ].map(([n, t], i) => (
            <div key={i} style={{ textAlign: "center" }}>
              <div
                style={{
                  fontFamily: "'Jura', sans-serif",
                  fontWeight: 700,
                  fontSize: 200,
                  lineHeight: 0.9,
                  letterSpacing: "-0.04em",
                  color: C.orange,
                }}
              >
                {n}
              </div>
              <h3
                style={{
                  fontFamily: "Inter, sans-serif",
                  fontWeight: 600,
                  fontSize: 26,
                  margin: "24px auto 0",
                  lineHeight: 1.25,
                  letterSpacing: "-0.01em",
                  maxWidth: 460,
                  color: C.paperInk,
                }}
              >
                {t}
              </h3>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

// ---------- Footer (final CTA with booking form) ----------
const CALENDLY_URL = "https://calendly.com/jessemusa2/30min";
// Google Form POST endpoint + entry IDs. Add email entry id here once the form
// is updated to use a regular Short-answer Email question (rather than the
// built-in "collect email" which requires Google sign-in).
const GOOGLE_FORM_ACTION =
  "https://docs.google.com/forms/d/e/1FAIpQLSeaRZoyYuP9YKD-oDu19y9pb11-iOLcgWdCO2WfrxRCGk7uaA/formResponse";
const FORM_ENTRY_IDS = {
  name: "entry.643842673",
  gym: "entry.714252564",
  email: "entry.1844120895",
};

function Footer() {
  const [form, setForm] = useState({ name: "", email: "", gym: "" });
  const [status, setStatus] = useState("idle"); // idle | submitting | submitted | error
  const onChange = (k) => (e) =>
    setForm((f) => ({ ...f, [k]: e.target.value }));
  async function onSubmit(e) {
    e.preventDefault();
    if (status === "submitting") return;
    if (!form.name.trim() || !form.email.trim() || !form.gym.trim()) return;
    setStatus("submitting");
    let ok = true;
    try {
      const body = new URLSearchParams();
      if (FORM_ENTRY_IDS.name) body.append(FORM_ENTRY_IDS.name, form.name);
      if (FORM_ENTRY_IDS.gym) body.append(FORM_ENTRY_IDS.gym, form.gym);
      if (FORM_ENTRY_IDS.email) body.append(FORM_ENTRY_IDS.email, form.email);
      await fetch(GOOGLE_FORM_ACTION, {
        method: "POST",
        mode: "no-cors",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: body.toString(),
      });
    } catch (_) {
      ok = false;
    }
    setStatus(ok ? "submitted" : "error");
    // Prefill Calendly with captured info and open in a new tab.
    const u = new URL(CALENDLY_URL);
    u.searchParams.set("name", form.name);
    u.searchParams.set("email", form.email);
    u.searchParams.set("a1", form.gym);
    window.open(u.toString(), "_blank", "noopener,noreferrer");
  }
  const submitting = status === "submitting";
  const submitted = status === "submitted";

  const inputStyle = {
    width: "100%",
    padding: "16px 18px",
    fontFamily: "Inter, sans-serif",
    fontSize: 15,
    color: C.bone,
    background: "rgba(244,243,238,0.05)",
    border: `1px solid ${C.divider}`,
    borderRadius: 12,
    outline: "none",
    boxSizing: "border-box",
  };

  return (
    <footer
      id="book"
      style={{
        background: C.ink2,
        scrollMarginTop: 72,
        color: C.bone,
        padding: "120px 64px 48px",
        minHeight: "100vh",
        borderTop: `1px solid ${C.divider}`,
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
      }}
    >
      <div style={{ maxWidth: 1280, margin: "0 auto", width: "100%" }}>
        <div
          style={{
            display: "grid",
            gridTemplateColumns: "1fr 480px",
            gap: 80,
            alignItems: "center",
            paddingBottom: 64,
            borderBottom: `1px solid ${C.divider}`,
          }}
        >
          <div>
            <h2
              style={{
                fontFamily: "Inter, sans-serif",
                fontWeight: 600,
                fontSize: 72,
                lineHeight: 0.98,
                letterSpacing: "-0.035em",
                margin: 0,
                maxWidth: 900,
                textWrap: "balance",
              }}
            >
              See it live.
              <br />
              Book a 15-min demo at your gym.
            </h2>
            <p
              style={{
                marginTop: 20,
                fontFamily: "Inter, sans-serif",
                fontSize: 18,
                color: C.fg2,
                maxWidth: 560,
              }}
            >
              Works alongside your current software — no migration required.
            </p>
          </div>
          <form
            onSubmit={onSubmit}
            style={{ display: "flex", flexDirection: "column", gap: 14 }}
          >
            <input
              style={inputStyle}
              type="text"
              placeholder="Your name"
              value={form.name}
              onChange={onChange("name")}
              required
            />
            <input
              style={inputStyle}
              type="email"
              placeholder="Email"
              value={form.email}
              onChange={onChange("email")}
              required
            />
            <input
              style={inputStyle}
              type="text"
              placeholder="Gym name"
              value={form.gym}
              onChange={onChange("gym")}
              required
            />
            <button
              type="submit"
              disabled={submitting || submitted}
              style={{
                background: submitted ? "rgba(244,243,238,0.10)" : C.orange,
                color: C.bone,
                border: submitted ? `1px solid ${C.divider}` : "none",
                padding: "18px 24px",
                borderRadius: 12,
                fontFamily: "Inter, sans-serif",
                fontWeight: 600,
                fontSize: 16,
                cursor: submitting || submitted ? "default" : "pointer",
                opacity: submitting ? 0.7 : 1,
                marginTop: 6,
                transition: "background 200ms ease, border-color 200ms ease",
              }}
            >
              {submitting
                ? "Sending…"
                : submitted
                  ? "✓ Thanks — Calendly opened in a new tab"
                  : "Book a demo →"}
            </button>
            {status === "error" && (
              <div
                style={{
                  fontFamily: "Inter, sans-serif",
                  fontSize: 13,
                  color: "rgba(255,108,45,0.9)",
                  marginTop: 4,
                }}
              >
                Couldn't record your details — but Calendly opened anyway. Feel
                free to book.
              </div>
            )}
          </form>
        </div>
        <div
          style={{
            paddingTop: 28,
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            fontFamily: "Inter, sans-serif",
            fontSize: 13,
            color: C.fg3,
          }}
        >
          <a href="#top" aria-label="CombatDen home" style={{ display: "inline-flex", alignItems: "center", lineHeight: 0 }}>
            <img src="assets/images/LogoTransparent.png" alt="CombatDen" style={{ height: 36, width: "auto", display: "block" }} />
          </a>
          <div>jesse@combatden.net · 832-871-2702</div>
        </div>
      </div>
    </footer>
  );
}

// ---------- FAQ ----------
function Faq() {
  const items = [
    {
      q: "Do I need to migrate data?",
      a: "No. Just member names, emails, rank (optional), and your class schedule. Everything else stays where it is.",
    },
    {
      q: "Can I customize the content?",
      a: "Yes — add YouTube videos of your own, and yours will be prioritized.",
    },
    {
      q: "Won't coach feedback take too long?",
      a: "Coaches speak their feedback and the app formats it. About 5 minutes per class.",
    },
  ];
  const [open, setOpen] = useState(-1);
  return (
    <section
      id="faq"
      style={{
        background: C.ink,
        color: C.bone,
        padding: "140px 64px",
        scrollMarginTop: 72,
      }}
    >
      <div style={{ maxWidth: 960, margin: "0 auto" }}>
        <div
          style={{
            fontFamily: "Inter, sans-serif",
            fontSize: SECTION_EYEBROW_SIZE,
            fontWeight: 700,
            letterSpacing: "0.22em",
            color: C.orange,
            textTransform: "uppercase",
            marginBottom: 24,
            textAlign: "center",
          }}
        >
          FAQ
        </div>
        <h2
          style={{
            fontFamily: "Inter, sans-serif",
            fontWeight: 600,
            fontSize: 56,
            lineHeight: 1,
            letterSpacing: "-0.03em",
            margin: "0 auto 64px",
            maxWidth: 800,
            textWrap: "balance",
            color: C.bone,
            textAlign: "center",
          }}
        >
          Questions, answered.
        </h2>

        <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
          {items.map((it, i) => {
            const isOpen = open === i;
            return (
              <div
                key={i}
                style={{
                  borderRadius: 16,
                  border: `1px solid ${C.divider}`,
                  background: "rgba(244,243,238,0.03)",
                  overflow: "hidden",
                }}
              >
                <button
                  onClick={() => setOpen(isOpen ? -1 : i)}
                  style={{
                    width: "100%",
                    background: "transparent",
                    border: "none",
                    textAlign: "left",
                    padding: "24px 28px",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    gap: 24,
                    cursor: "pointer",
                    fontFamily: "Inter, sans-serif",
                    fontSize: 20,
                    fontWeight: 600,
                    color: C.bone,
                    letterSpacing: "-0.01em",
                  }}
                >
                  <span>{it.q}</span>
                  <span
                    style={{
                      color: C.orange,
                      fontSize: 28,
                      fontWeight: 400,
                      transform: isOpen ? "rotate(45deg)" : "rotate(0)",
                      transition: "transform 240ms ease",
                      lineHeight: 1,
                      display: "inline-block",
                    }}
                  >
                    +
                  </span>
                </button>
                <div
                  style={{
                    maxHeight: isOpen ? 240 : 0,
                    overflow: "hidden",
                    transition: "max-height 320ms ease",
                  }}
                >
                  <p
                    style={{
                      margin: 0,
                      padding: "0 28px 24px",
                      fontFamily: "Inter, sans-serif",
                      fontSize: 16,
                      lineHeight: 1.55,
                      color: C.fg2,
                      maxWidth: 760,
                    }}
                  >
                    {it.a}
                  </p>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
}

// ---------- Root ----------
function App() {
  return (
    <div style={{ background: C.ink, minHeight: "100vh" }}>
      <Nav />
      <Hero />
      <Problem />
      <Solution />
      <HowItWorks />
      <Loyalty />
      <WhyItMatters />
      <Faq />
      <Footer />
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
