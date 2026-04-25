// CombatDen — Pricing screen
// Matches the landing manifesto aesthetic: ink ground, orange accent, pulsing
// glow on the hero, Jura for hero numbers, Inter for everything else.

const { useEffect, useState } = React;

const C = {
  ink: "#121619",
  bone: "#F4F3EE",
  orange: "#FF6C2D",
  fg2: "rgba(244,243,238,0.72)",
  fg3: "rgba(244,243,238,0.5)",
  fg4: "rgba(244,243,238,0.25)",
  divider: "rgba(244,243,238,0.15)",
  cardBg: "rgba(244,243,238,0.04)",
  cardBgHover: "rgba(244,243,238,0.07)",
  cardOrangeBg: "rgba(255,108,45,0.10)",
  cardOrangeBorder: "rgba(255,108,45,0.45)",
};

const BP = { phone: 767, tablet: 1199 };
function useBreakpoint() {
  const get = () => {
    if (typeof window === "undefined") return "desktop";
    const w = window.innerWidth;
    if (w <= BP.phone) return "phone";
    if (w <= BP.tablet) return "tablet";
    return "desktop";
  };
  const [bp, setBp] = useState(get);
  useEffect(() => {
    const on = () => setBp(get());
    window.addEventListener("resize", on);
    return () => window.removeEventListener("resize", on);
  }, []);
  return bp;
}

// ---------- Nav ----------
const navLink = { color: "inherit", textDecoration: "none", cursor: "pointer" };

function Nav() {
  const bp = useBreakpoint();
  const showLinks = bp !== "phone";
  const padX = bp === "phone" ? 16 : bp === "tablet" ? 28 : 48;
  const navHeight = bp === "phone" ? 56 : bp === "tablet" ? 64 : 72;
  const logoH = bp === "phone" ? 28 : bp === "tablet" ? 34 : 40;
  return (
    <div
      style={{
        position: "sticky",
        top: 0,
        zIndex: 50,
        height: navHeight,
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        padding: `0 ${padX}px`,
        background: "rgba(18,22,25,0.82)",
        backdropFilter: "blur(16px)",
        WebkitBackdropFilter: "blur(16px)",
        borderBottom: `1px solid ${C.divider}`,
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: bp === "desktop" ? 44 : 24 }}>
        <a
          href="index.html"
          aria-label="CombatDen home"
          style={{
            display: "inline-flex",
            alignItems: "center",
            lineHeight: 0,
            textDecoration: "none",
          }}
        >
          <img
            src="assets/images/LogoTransparent.png"
            alt="CombatDen"
            style={{ height: logoH, width: "auto", display: "block" }}
          />
        </a>
        {showLinks && (
          <div
            style={{
              display: "flex",
              gap: 28,
              fontFamily: "Inter, sans-serif",
              fontSize: 14,
              color: "rgba(244,243,238,0.7)",
            }}
          >
            <a href="index.html#how-it-works" style={navLink}>How it works</a>
            <a href="index.html#why" style={navLink}>Why it matters</a>
            <a
              href="pricing.html"
              style={{ ...navLink, color: C.bone, fontWeight: 600 }}
              aria-current="page"
            >
              Pricing
            </a>
            <a href="index.html#faq" style={navLink}>FAQ</a>
          </div>
        )}
      </div>
      <a
        href="#book"
        style={{
          background: C.orange,
          color: C.bone,
          border: "none",
          padding: bp === "phone" ? "10px 16px" : "12px 22px",
          borderRadius: 999,
          fontFamily: "Inter, sans-serif",
          fontWeight: 600,
          fontSize: 13,
          cursor: "pointer",
          letterSpacing: "0.01em",
          textDecoration: "none",
          display: "inline-block",
          whiteSpace: "nowrap",
        }}
      >
        {bp === "phone" ? "Book demo" : "Book a demo →"}
      </a>
    </div>
  );
}

// ---------- Hero ----------
// Background: full-bleed hairline grid + soft top-edge orange wash that fades
// into the page below. No hard radial cutoff edges.
function Hero() {
  const bp = useBreakpoint();

  const heroPad =
    bp === "phone"
      ? "80px 20px 48px"
      : bp === "tablet"
      ? "120px 40px 72px"
      : "160px 64px 96px";
  const h1Size = bp === "phone" ? 44 : bp === "tablet" ? 72 : 104;
  const tagSize = bp === "phone" ? 16 : bp === "tablet" ? 18 : 20;
  const eyebrowSize = bp === "phone" ? 14 : 18;
  const gridSize = bp === "phone" ? 40 : 64;

  return (
    <section
      style={{
        position: "relative",
        padding: heroPad,
        textAlign: "center",
        overflow: "hidden",
        background: C.ink,
      }}
    >
      <div
        aria-hidden
        style={{
          position: "absolute",
          inset: 0,
          background:
            "linear-gradient(180deg, rgba(255,108,45,0.20) 0%, rgba(255,108,45,0.06) 38%, transparent 75%)",
          pointerEvents: "none",
        }}
      />
      <div
        aria-hidden
        style={{
          position: "absolute",
          inset: 0,
          backgroundImage:
            "linear-gradient(rgba(244,243,238,0.055) 1px, transparent 1px), linear-gradient(90deg, rgba(244,243,238,0.055) 1px, transparent 1px)",
          backgroundSize: `${gridSize}px ${gridSize}px`,
          maskImage:
            "radial-gradient(ellipse 90% 100% at 50% 30%, #000 30%, transparent 90%)",
          WebkitMaskImage:
            "radial-gradient(ellipse 90% 100% at 50% 30%, #000 30%, transparent 90%)",
          pointerEvents: "none",
        }}
      />
      <div
        aria-hidden
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          bottom: 0,
          height: "40%",
          background:
            "linear-gradient(180deg, transparent 0%, rgba(18,22,25,0.85) 70%, #121619 100%)",
          pointerEvents: "none",
        }}
      />
      <div style={{ position: "relative", zIndex: 2 }}>
        <div
          style={{
            fontFamily: "'Jura', sans-serif",
            fontSize: eyebrowSize,
            fontWeight: 700,
            letterSpacing: "0.22em",
            color: C.orange,
            textTransform: "uppercase",
          }}
        >
          Pricing
        </div>
        <h1
          style={{
            fontFamily: "Inter, sans-serif",
            fontWeight: 600,
            fontSize: h1Size,
            lineHeight: 1.0,
            letterSpacing: "-0.035em",
            color: C.bone,
            margin: "28px auto 0",
            maxWidth: 1100,
            textWrap: "balance",
          }}
        >
          Pricing that scales{" "}
          <span style={{ color: C.orange }}>with your gym.</span>
        </h1>
        <p
          style={{
            fontFamily: "Inter, sans-serif",
            fontSize: tagSize,
            lineHeight: 1.5,
            color: C.fg2,
            maxWidth: 640,
            margin: "32px auto 0",
          }}
        >
          Flat monthly rate based on member count. No setup fees. Cancel
          anytime.
        </p>
      </div>
    </section>
  );
}

// ---------- Plan cards ----------
const PLANS = [
  {
    name: "Starter",
    range: "0 – 100 members",
    price: "69.99",
    cadence: "/mo",
    featured: false,
    cta: "Book a demo",
  },
  {
    name: "Growth",
    range: "100 – 200 members",
    price: "99.99",
    cadence: "/mo",
    featured: true,
    cta: "Book a demo",
    badge: null,
  },
  {
    name: "Scale",
    range: "200+ members",
    price: "149.99",
    cadence: "/mo",
    featured: false,
    cta: "Book a demo",
  },
];

const FEATURES = [
  "Member App (iOS & Android)",
  "Retention Engine",
  "Loyalty Engine",
  "Class Management",
];

function CheckIcon({ color = C.orange, size = 18 }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke={color}
      strokeWidth="2.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
      style={{ flex: "0 0 auto" }}
    >
      <polyline points="20 6 9 17 4 12" />
    </svg>
  );
}

function PlanCard({ plan, bp }) {
  const featured = plan.featured;
  const padding = bp === "phone" ? 28 : 36;
  const priceSize = bp === "phone" ? 72 : bp === "tablet" ? 88 : 104;
  const [hover, setHover] = useState(false);

  const [whole, fraction] = plan.price.split(".");

  return (
    <div
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        position: "relative",
        background: featured ? C.cardOrangeBg : hover ? C.cardBgHover : C.cardBg,
        border: featured
          ? `1.5px solid ${C.cardOrangeBorder}`
          : `1px solid ${C.divider}`,
        borderRadius: 32,
        padding,
        display: "flex",
        flexDirection: "column",
        boxShadow: featured
          ? "0 24px 60px rgba(255,108,45,0.18), 0 4px 4px rgba(0,0,0,0.25)"
          : "0 4px 4px rgba(0,0,0,0.25)",
        transition:
          "transform 200ms cubic-bezier(0.16, 1, 0.3, 1), background 200ms, border-color 200ms",
        transform: hover ? "translateY(-4px)" : "translateY(0)",
        minHeight: bp === "phone" ? "auto" : 560,
      }}
    >
      {featured && plan.badge && (
        <div
          style={{
            position: "absolute",
            top: -14,
            left: padding,
            background: C.orange,
            color: C.bone,
            padding: "6px 14px",
            borderRadius: 999,
            fontFamily: "'Jura', sans-serif",
            fontWeight: 700,
            fontSize: 11,
            letterSpacing: "0.18em",
            textTransform: "uppercase",
          }}
        >
          {plan.badge}
        </div>
      )}

      <div>
        <div
          style={{
            fontFamily: "Inter, sans-serif",
            fontWeight: 700,
            fontSize: bp === "phone" ? 28 : 32,
            letterSpacing: "-0.02em",
            color: C.bone,
            lineHeight: 1,
          }}
        >
          {plan.name}
        </div>
        <div
          style={{
            fontFamily: "'Jura', sans-serif",
            fontWeight: 600,
            fontSize: 13,
            letterSpacing: "0.22em",
            textTransform: "uppercase",
            color: featured ? C.orange : C.fg3,
            marginTop: 14,
          }}
        >
          {plan.range}
        </div>
      </div>

      <div style={{ marginTop: 36, display: "flex", alignItems: "flex-start" }}>
        <span
          style={{
            fontFamily: "'Jura', sans-serif",
            fontWeight: 700,
            fontSize: priceSize * 0.45,
            color: C.bone,
            lineHeight: 1,
            marginTop: priceSize * 0.12,
            marginRight: 4,
            letterSpacing: "-0.02em",
          }}
        >
          $
        </span>
        <span
          style={{
            fontFamily: "'Jura', sans-serif",
            fontWeight: 700,
            fontSize: priceSize,
            lineHeight: 0.85,
            letterSpacing: "-0.04em",
            color: C.bone,
          }}
        >
          {whole}
        </span>
        <span
          style={{
            fontFamily: "'Jura', sans-serif",
            fontWeight: 700,
            fontSize: priceSize * 0.32,
            lineHeight: 1,
            letterSpacing: "-0.02em",
            color: C.fg2,
            marginTop: priceSize * 0.18,
            marginLeft: 2,
          }}
        >
          .{fraction}
        </span>
        <span
          style={{
            fontFamily: "Inter, sans-serif",
            fontWeight: 500,
            fontSize: 16,
            color: C.fg3,
            alignSelf: "flex-end",
            marginBottom: priceSize * 0.12,
            marginLeft: 8,
            letterSpacing: "0.02em",
          }}
        >
          {plan.cadence}
        </span>
      </div>

      <div
        style={{
          marginTop: 32,
          paddingTop: 28,
          borderTop: `1px solid ${C.divider}`,
        }}
      >
        <div
          style={{
            fontFamily: "Inter, sans-serif",
            fontWeight: 600,
            fontSize: 13,
            letterSpacing: "0.12em",
            textTransform: "uppercase",
            color: C.fg3,
            marginBottom: 20,
          }}
        >
          All features included
        </div>
        <ul
          style={{
            listStyle: "none",
            padding: 0,
            margin: 0,
            display: "flex",
            flexDirection: "column",
            gap: 14,
          }}
        >
          {FEATURES.map((f) => (
            <li
              key={f}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 12,
                fontFamily: "Inter, sans-serif",
                fontSize: 16,
                color: C.bone,
                letterSpacing: "0.01em",
              }}
            >
              <CheckIcon color={C.orange} />
              <span>{f}</span>
            </li>
          ))}
        </ul>
      </div>

      <div style={{ flex: 1 }} />
      <a
        href="#book"
        style={{
          marginTop: 32,
          display: "block",
          textAlign: "center",
          background: featured ? C.orange : "transparent",
          color: C.bone,
          border: featured ? "none" : `2px solid ${C.bone}`,
          padding: featured ? "18px 24px" : "16px 24px",
          borderRadius: 999,
          fontFamily: "Inter, sans-serif",
          fontWeight: 600,
          fontSize: 15,
          letterSpacing: "0.01em",
          textDecoration: "none",
          cursor: "pointer",
          transition: "background 200ms, opacity 200ms",
        }}
      >
        {plan.cta}
      </a>
    </div>
  );
}

function PricingGrid() {
  const bp = useBreakpoint();
  const cols =
    bp === "phone" ? "1fr" : bp === "tablet" ? "1fr" : "1fr 1fr 1fr";
  const pad =
    bp === "phone" ? "32px 20px 96px" : bp === "tablet" ? "48px 40px 120px" : "64px 64px 160px";
  const gap = bp === "phone" ? 24 : 28;
  return (
    <section
      style={{
        background: C.ink,
        padding: pad,
      }}
    >
      <div
        style={{
          maxWidth: 1280,
          margin: "0 auto",
          display: "grid",
          gridTemplateColumns: cols,
          gap,
          alignItems: "stretch",
        }}
      >
        {PLANS.map((p) => (
          <PlanCard key={p.name} plan={p} bp={bp} />
        ))}
      </div>

      <div
        style={{
          maxWidth: 1280,
          margin: bp === "phone" ? "48px auto 0" : "72px auto 0",
          display: "grid",
          gridTemplateColumns: bp === "desktop" ? "repeat(3, 1fr)" : "1fr",
          gap: bp === "phone" ? 28 : 40,
          textAlign: "center",
        }}
      >
        {[
          ["No setup fees", "Onboarding and import included."],
          ["No card migration", "Works alongside your current software."],
          ["Cancel anytime", "Month-to-month. No long-term contracts."],
        ].map(([t, s]) => (
          <div key={t}>
            <div
              style={{
                fontFamily: "'Jura', sans-serif",
                fontWeight: 700,
                fontSize: 14,
                letterSpacing: "0.22em",
                textTransform: "uppercase",
                color: C.orange,
              }}
            >
              {t}
            </div>
            <div
              style={{
                fontFamily: "Inter, sans-serif",
                fontSize: 15,
                color: C.fg2,
                marginTop: 10,
                letterSpacing: "0.02em",
              }}
            >
              {s}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

// ---------- Footer (book demo form) ----------
const CALENDLY_URL = "https://calendly.com/jessemusa2/30min";
const GOOGLE_FORM_ACTION =
  "https://docs.google.com/forms/d/e/1FAIpQLSeaRZoyYuP9YKD-oDu19y9pb11-iOLcgWdCO2WfrxRCGk7uaA/formResponse";
const FORM_ENTRY_IDS = {
  name: "entry.643842673",
  gym: "entry.714252564",
  email: "entry.1844120895",
};

function Footer() {
  const bp = useBreakpoint();
  const [form, setForm] = useState({ name: "", email: "", gym: "" });
  const [status, setStatus] = useState("idle");
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
      body.append(FORM_ENTRY_IDS.name, form.name);
      body.append(FORM_ENTRY_IDS.gym, form.gym);
      body.append(FORM_ENTRY_IDS.email, form.email);
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
    const u = new URL(CALENDLY_URL);
    u.searchParams.set("name", form.name);
    u.searchParams.set("email", form.email);
    u.searchParams.set("a1", form.gym);
    window.open(u.toString(), "_blank", "noopener,noreferrer");
  }

  const submitting = status === "submitting";
  const submitted = status === "submitted";

  const pad =
    bp === "phone"
      ? "80px 20px 48px"
      : bp === "tablet"
      ? "96px 40px 48px"
      : "120px 64px 48px";
  const grid = bp === "desktop" ? "1fr 480px" : "1fr";
  const gap = bp === "desktop" ? 80 : 40;
  const align = bp === "desktop" ? "left" : "center";
  const h2 = bp === "phone" ? 36 : bp === "tablet" ? 52 : 72;
  const tag = bp === "phone" ? 16 : bp === "tablet" ? 17 : 18;
  const inputPad = bp === "desktop" ? "16px 18px" : "14px 16px";
  const logoH = bp === "phone" ? 24 : bp === "tablet" ? 26 : 28;

  const inputStyle = {
    width: "100%",
    padding: inputPad,
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
        background: C.ink,
        color: C.bone,
        padding: pad,
        scrollMarginTop: 80,
      }}
    >
      <div
        style={{
          maxWidth: bp === "desktop" ? 1280 : 720,
          margin: "0 auto",
          width: "100%",
          textAlign: align,
        }}
      >
        <div
          style={{
            display: "grid",
            gridTemplateColumns: grid,
            gap,
            alignItems: "center",
            justifyItems: align === "center" ? "center" : "stretch",
            paddingBottom: bp === "phone" ? 40 : 64,
          }}
        >
          <div style={{ width: "100%" }}>
            <h2
              style={{
                fontFamily: "Inter, sans-serif",
                fontWeight: 600,
                fontSize: h2,
                lineHeight: 0.98,
                letterSpacing: "-0.035em",
                margin: align === "center" ? "0 auto" : 0,
                maxWidth: 900,
                textWrap: "balance",
              }}
            >
              See it live.
              <br />
              Book a 15-min demo.
            </h2>
            <p
              style={{
                marginTop: bp === "desktop" ? 20 : 16,
                marginLeft: align === "center" ? "auto" : undefined,
                marginRight: align === "center" ? "auto" : undefined,
                fontFamily: "Inter, sans-serif",
                fontSize: tag,
                color: C.fg2,
                maxWidth: 560,
              }}
            >
              Works alongside your current software — no card migration
              required.
            </p>
          </div>
          <form
            onSubmit={onSubmit}
            style={{
              display: "flex",
              flexDirection: "column",
              gap: bp === "desktop" ? 14 : 12,
              width: "100%",
            }}
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
                padding: bp === "desktop" ? "18px 24px" : "16px 22px",
                borderRadius: 12,
                fontFamily: "Inter, sans-serif",
                fontWeight: 600,
                fontSize: bp === "desktop" ? 16 : 15,
                cursor: submitting || submitted ? "default" : "pointer",
                opacity: submitting ? 0.7 : 1,
                marginTop: 6,
                transition: "background 200ms ease",
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
                Couldn't record your details — but Calendly opened anyway.
              </div>
            )}
          </form>
        </div>
        <div
          style={{
            paddingTop: bp === "desktop" ? 28 : 24,
            display: "flex",
            flexDirection: bp === "phone" ? "column" : "row",
            justifyContent: bp === "phone" ? "center" : "space-between",
            alignItems: "center",
            gap: bp === "phone" ? 12 : 16,
            fontFamily: "Inter, sans-serif",
            fontSize: 13,
            color: C.fg3,
          }}
        >
          <a
            href="index.html"
            aria-label="CombatDen home"
            style={{
              display: "inline-flex",
              alignItems: "center",
              lineHeight: 0,
            }}
          >
            <img
              src="assets/images/LogoTransparent.png"
              alt="CombatDen"
              style={{ height: logoH, width: "auto", display: "block" }}
            />
          </a>
          <div>jesse@combatden.net · 832-871-2702</div>
          <div style={{ color: C.fg4 }}>
            © {new Date().getFullYear()} CombatDen
          </div>
        </div>
      </div>
    </footer>
  );
}

// ---------- App ----------
function App() {
  return (
    <div style={{ background: C.ink, minHeight: "100vh" }}>
      <Nav />
      <Hero />
      <PricingGrid />
      <Footer />
    </div>
  );
}

const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App />);
