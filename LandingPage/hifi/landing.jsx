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

// ---------- Responsive size table ----------
// Desktop column is copied verbatim from the original hardcoded literals so
// >=1200px rendering is byte-identical. Tablet/phone columns are overrides.
const BP = { phone: 767, tablet: 1199 }; // phone <=767, tablet 768-1199, desktop >=1200

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

const SIZES = {
  desktop: {
    // Nav
    navHeight: 72,
    navPadX: 48,
    navGapOuter: 44,
    navGapInner: 28,
    navLogoH: 40,
    navBtnPad: "12px 22px",
    navShowLinks: true,
    navBookLabel: "Book a demo →",
    // Hero
    heroMinH: 820,
    heroPad: "160px 64px 200px",
    heroGlowW: 1900,
    heroGlowH: 1500,
    heroEyebrow: 18,
    heroH1: 104,
    heroH1MaxW: 1200,
    heroTag: 20,
    heroTagMaxW: 640,
    heroCtaMarginTop: 48,
    heroCtaGap: 14,
    heroCtaDir: "row",
    heroCtaPad: "18px 32px",
    heroCtaFont: 15,
    // Problem
    problemPad: "280px 64px",
    problemMaxW: 1200,
    problemEyebrow: 18,
    problemEyebrowMB: 32,
    problemNumGap: 40,
    problemNum: 280,
    problemH2: 48,
    problemH2MaxW: 720,
    problemSourceMT: 56,
    problemAlign: "center",
    problemInnerDir: "column",
    problemInnerAlign: "center",
    problemInnerJustify: "center",
    // Solution
    solutionPad: "140px 64px",
    solutionMaxW: 1100,
    solutionEyebrow: 18,
    solutionEyebrowMB: 32,
    solutionH2: 88,
    solutionH2MaxW: 1000,
    // HowItWorks
    howPad: "120px 64px 180px",
    howMaxW: 1280,
    howEyebrow: 18,
    howEyebrowMB: 16,
    howH2: 48,
    howH2MaxW: 900,
    howGridGap: 100,
    howGrid: "1fr 1fr",
    howPhoneMax: 340,
    howImagesGap: 18,
    howArrow: 40,
    howStepNum: 72,
    howStepH3: 44,
    howStepCopy: 18,
    howStepCopyMaxW: 480,
    howStepPadLeft: 50,
    howSticky: true,
    howTitlePad: "48px 0 32px",
    howAlign: "left",
    loopPinned: true,
    loopItemGap: 40,
    loopDiscrete: false,
    footerAlign: "left",
    footerItemsAlign: "stretch",
    // Loyalty section wrapper
    loyaltyPad: "160px 64px",
    loyaltyMaxW: 1280,
    // LoopSequence
    loopMaxW: 1100,
    loopPadX: 40,
    loopH2: 48,
    loopH2MaxW: 800,
    loopCircle: 160,
    loopLineTop: 80,
    loopPtsFont: 54,
    loopPtsLabelFont: 12,
    loopLabelMT: 36,
    loopEyebrowMB: 16,
    loopTitleMB: 40,
    loopDisclaimerMB: 56,
    loopPinVhPerStep: 100,
    loopDir: "row",
    // DualBenefit
    rewardsPad: "160px 64px",
    rewardsMaxW: 1280,
    rewardsEyebrow: 18,
    rewardsEyebrowMB: 24,
    rewardsH2: 48,
    rewardsH2MB: 140,
    rewardsH2MaxW: 900,
    // WhyItMatters
    whyPad: "120px 64px",
    whyMaxW: 1280,
    whyH2: 80,
    whyH2MB: 80,
    whyH2MaxW: 1100,
    whyGrid: "1fr 1fr",
    whyGap: 80,
    whyGridMT: 40,
    whyNum: 200,
    whyStatH3: 26,
    whyStatH3MT: 24,
    whyStatH3MaxW: 460,
    // Faq
    faqPad: "140px 64px",
    faqMaxW: 960,
    faqEyebrowMB: 24,
    faqH2: 56,
    faqH2MB: 64,
    faqH2MaxW: 800,
    faqQ: 20,
    faqA: 16,
    faqAMaxW: 760,
    faqBtnPad: "24px 28px",
    faqAPad: "0 28px 24px",
    faqPlusFont: 28,
    faqGap: 14,
    faqBtnGap: 24,
    // Footer
    footerPad: "120px 64px 48px",
    footerMaxW: 1280,
    footerGrid: "1fr 480px",
    footerGap: 80,
    footerPadBottom: 64,
    footerH2: 72,
    footerH2MaxW: 900,
    footerTag: 18,
    footerTagMaxW: 560,
    footerTagMT: 20,
    footerFormGap: 14,
    footerInputFont: 15,
    footerInputPad: "16px 18px",
    footerBtnPad: "18px 24px",
    footerBtnFont: 16,
    footerBottomDir: "row",
    footerBottomGap: 0,
    footerLogoH: 36,
    footerBottomPT: 28,
  },
  tablet: {
    navHeight: 64,
    navPadX: 28,
    navGapOuter: 24,
    navGapInner: 16,
    navLogoH: 36,
    navBtnPad: "10px 18px",
    navShowLinks: true,
    navBookLabel: "Book a demo →",

    heroMinH: 720,
    heroPad: "120px 40px 140px",
    heroGlowW: 1200,
    heroGlowH: 900,
    heroEyebrow: 16,
    heroH1: 72,
    heroH1MaxW: 720,
    heroTag: 18,
    heroTagMaxW: 520,
    heroCtaMarginTop: 40,
    heroCtaGap: 12,
    heroCtaDir: "row",
    heroCtaPad: "16px 28px",
    heroCtaFont: 15,

    problemPad: "180px 40px",
    problemMaxW: 1200,
    problemEyebrow: 16,
    problemEyebrowMB: 24,
    problemNumGap: 28,
    problemNum: 180,
    problemH2: 40,
    problemH2MaxW: 640,
    problemSourceMT: 40,
    problemAlign: "center",
    problemInnerDir: "column",
    problemInnerAlign: "center",
    problemInnerJustify: "center",

    solutionPad: "100px 40px",
    solutionMaxW: 1100,
    solutionEyebrow: 16,
    solutionEyebrowMB: 24,
    solutionH2: 64,
    solutionH2MaxW: 820,

    howPad: "96px 40px 140px",
    howMaxW: 1280,
    howEyebrow: 16,
    howEyebrowMB: 14,
    howH2: 48,
    howH2MaxW: 720,
    howGridGap: 0,
    howGrid: "1fr",
    howPhoneMax: 260,
    howImagesGap: 12,
    howArrow: 32,
    howStepNum: 56,
    howStepH3: 32,
    howStepCopy: 17,
    howStepCopyMaxW: 520,
    howStepPadLeft: 0,
    howSticky: false,
    howTitlePad: "36px 0 24px",
    howAlign: "center",
    loopPinned: false,
    loopItemGap: 140,
    loopDiscrete: true,
    footerAlign: "center",
    footerItemsAlign: "center",

    loyaltyPad: "120px 40px 140px",
    loyaltyMaxW: 1280,

    loopMaxW: 720,
    loopPadX: 24,
    loopH2: 40,
    loopH2MaxW: 640,
    loopCircle: 120,
    loopLineTop: 60,
    loopPtsFont: 40,
    loopPtsLabelFont: 11,
    loopLabelMT: 24,
    loopEyebrowMB: 14,
    loopTitleMB: 32,
    loopDisclaimerMB: 40,
    loopPinVhPerStep: 100,
    loopDir: "column",

    rewardsPad: "120px 40px",
    rewardsMaxW: 1280,
    rewardsEyebrow: 16,
    rewardsEyebrowMB: 20,
    rewardsH2: 48,
    rewardsH2MB: 80,
    rewardsH2MaxW: 720,

    whyPad: "96px 40px",
    whyMaxW: 1280,
    whyH2: 56,
    whyH2MB: 56,
    whyH2MaxW: 900,
    whyGrid: "1fr 1fr",
    whyGap: 48,
    whyGridMT: 32,
    whyNum: 140,
    whyStatH3: 22,
    whyStatH3MT: 18,
    whyStatH3MaxW: 380,

    faqPad: "100px 40px",
    faqMaxW: 720,
    faqEyebrowMB: 20,
    faqH2: 44,
    faqH2MB: 48,
    faqH2MaxW: 640,
    faqQ: 18,
    faqA: 15,
    faqAMaxW: 640,
    faqBtnPad: "20px 22px",
    faqAPad: "0 22px 20px",
    faqPlusFont: 24,
    faqGap: 12,
    faqBtnGap: 16,

    footerPad: "96px 40px 48px",
    footerMaxW: 720,
    footerGrid: "1fr",
    footerGap: 40,
    footerPadBottom: 48,
    footerH2: 52,
    footerH2MaxW: "100%",
    footerTag: 17,
    footerTagMaxW: "100%",
    footerTagMT: 16,
    footerFormGap: 12,
    footerInputFont: 15,
    footerInputPad: "14px 16px",
    footerBtnPad: "16px 22px",
    footerBtnFont: 15,
    footerBottomDir: "row",
    footerBottomGap: 0,
    footerLogoH: 32,
    footerBottomPT: 24,
  },
  phone: {
    navHeight: 56,
    navPadX: 16,
    navGapOuter: 12,
    navGapInner: 0,
    navLogoH: 32,
    navBtnPad: "10px 16px",
    navShowLinks: false,
    navBookLabel: "Book demo",

    heroMinH: 640,
    heroPad: "80px 20px 96px",
    heroGlowW: 800,
    heroGlowH: 600,
    heroEyebrow: 14,
    heroH1: 40,
    heroH1MaxW: "100%",
    heroTag: 16,
    heroTagMaxW: "100%",
    heroCtaMarginTop: 32,
    heroCtaGap: 12,
    heroCtaDir: "column",
    heroCtaPad: "16px 24px",
    heroCtaFont: 15,

    problemPad: "120px 20px",
    problemMaxW: "100%",
    problemEyebrow: 14,
    problemEyebrowMB: 20,
    problemNumGap: 16,
    problemNum: 104,
    problemH2: 28,
    problemH2MaxW: "100%",
    problemSourceMT: 32,
    problemAlign: "center",
    problemInnerDir: "column",
    problemInnerAlign: "center",
    problemInnerJustify: "center",

    solutionPad: "72px 20px",
    solutionMaxW: "100%",
    solutionEyebrow: 14,
    solutionEyebrowMB: 20,
    solutionH2: 36,
    solutionH2MaxW: "100%",

    howPad: "64px 20px 96px",
    howMaxW: "100%",
    howEyebrow: 14,
    howEyebrowMB: 12,
    howH2: 32,
    howH2MaxW: "100%",
    howGridGap: 0,
    howGrid: "1fr",
    howPhoneMax: 240,
    howImagesGap: 8,
    howArrow: 24,
    howStepNum: 42,
    howStepH3: 26,
    howStepCopy: 16,
    howStepCopyMaxW: "100%",
    howStepPadLeft: 0,
    howSticky: false,
    howTitlePad: "24px 0 20px",
    howAlign: "center",
    loopPinned: false,
    loopItemGap: 120,
    loopDiscrete: true,
    footerAlign: "center",
    footerItemsAlign: "center",

    loyaltyPad: "140px 20px 160px",
    loyaltyMaxW: "100%",

    loopMaxW: "100%",
    loopPadX: 8,
    loopH2: 28,
    loopH2MaxW: "100%",
    loopCircle: 132,
    loopLineTop: 66,
    loopPtsFont: 42,
    loopPtsLabelFont: 11,
    loopLabelMT: 16,
    loopEyebrowMB: 12,
    loopTitleMB: 24,
    loopDisclaimerMB: 32,
    loopPinVhPerStep: 80,
    loopDir: "column",

    rewardsPad: "80px 20px",
    rewardsMaxW: "100%",
    rewardsEyebrow: 14,
    rewardsEyebrowMB: 16,
    rewardsH2: 32,
    rewardsH2MB: 48,
    rewardsH2MaxW: "100%",

    whyPad: "72px 20px",
    whyMaxW: "100%",
    whyH2: 36,
    whyH2MB: 40,
    whyH2MaxW: "100%",
    whyGrid: "1fr",
    whyGap: 40,
    whyGridMT: 24,
    whyNum: 88,
    whyStatH3: 18,
    whyStatH3MT: 14,
    whyStatH3MaxW: "100%",

    faqPad: "72px 20px",
    faqMaxW: "100%",
    faqEyebrowMB: 16,
    faqH2: 30,
    faqH2MB: 32,
    faqH2MaxW: "100%",
    faqQ: 17,
    faqA: 15,
    faqAMaxW: "100%",
    faqBtnPad: "18px 18px",
    faqAPad: "0 18px 18px",
    faqPlusFont: 22,
    faqGap: 10,
    faqBtnGap: 12,

    footerPad: "80px 20px 48px",
    footerMaxW: "100%",
    footerGrid: "1fr",
    footerGap: 32,
    footerPadBottom: 40,
    footerH2: 36,
    footerH2MaxW: "100%",
    footerTag: 16,
    footerTagMaxW: "100%",
    footerTagMT: 14,
    footerFormGap: 12,
    footerInputFont: 15,
    footerInputPad: "14px 16px",
    footerBtnPad: "16px 22px",
    footerBtnFont: 15,
    footerBottomDir: "column",
    footerBottomGap: 12,
    footerLogoH: 28,
    footerBottomPT: 20,
  },
};

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
  const S = SIZES[useBreakpoint()];
  return (
    <div
      style={{
        position: "sticky",
        top: 0,
        zIndex: 50,
        height: S.navHeight,
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        padding: `0 ${S.navPadX}px`,
        background: "rgba(18,22,25,0.82)",
        backdropFilter: "blur(16px)",
        WebkitBackdropFilter: "blur(16px)",
        borderBottom: `1px solid ${C.divider}`,
      }}
    >
      <div
        style={{ display: "flex", alignItems: "center", gap: S.navGapOuter }}
      >
        <a
          href="#top"
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
            style={{ height: S.navLogoH, width: "auto", display: "block" }}
          />
        </a>
        {S.navShowLinks && (
          <div
            style={{
              display: "flex",
              gap: S.navGapInner,
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
              onClick={(e) => {
                const el = document.getElementById("why");
                if (!el) return;
                e.preventDefault();
                el.scrollIntoView({ behavior: "smooth", block: "center" });
              }}
              style={{
                color: "inherit",
                textDecoration: "none",
                cursor: "pointer",
              }}
            >
              Why it matters
            </a>
            <a
              href="pricing.html"
              style={{
                color: "inherit",
                textDecoration: "none",
                cursor: "pointer",
              }}
            >
              Pricing
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
        )}
      </div>
      <a
        href="#book"
        style={{
          background: C.orange,
          color: C.bone,
          border: "none",
          padding: S.navBtnPad,
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
        {S.navBookLabel}
      </a>
    </div>
  );
}

// ---------- Hero (Glow A — bottom gradient pulsating bigger/smaller, always large) ----------
function Hero() {
  const S = SIZES[useBreakpoint()];
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
        minHeight: S.heroMinH,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        padding: S.heroPad,
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
          width: S.heroGlowW,
          height: S.heroGlowH,
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
            fontSize: S.heroEyebrow,
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
            fontSize: S.heroH1,
            lineHeight: 1.0,
            letterSpacing: "-0.035em",
            color: C.bone,
            margin: "28px 0 0",
            maxWidth: S.heroH1MaxW,
            textWrap: "balance",
          }}
        >
          A member app that stops fighters from quitting.
        </h1>
        <p
          style={{
            fontFamily: "Inter, sans-serif",
            fontSize: S.heroTag,
            lineHeight: 1.5,
            color: C.fg2,
            maxWidth: S.heroTagMaxW,
            margin: "36px auto 0",
          }}
        >
          Works alongside your current software — no card migration required.
        </p>
        <div
          style={{
            marginTop: S.heroCtaMarginTop,
            display: "flex",
            flexDirection: S.heroCtaDir,
            alignItems: "center",
            justifyContent: "center",
            gap: S.heroCtaGap,
          }}
        >
          <a
            href="#book"
            style={{
              background: C.orange,
              color: C.bone,
              border: "none",
              padding: S.heroCtaPad,
              borderRadius: 999,
              fontFamily: "Inter, sans-serif",
              fontWeight: 600,
              fontSize: S.heroCtaFont,
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
// Slide-in mirrors ResultBlock: the section is 150vh so there is scroll room
// for a bottom-to-centre animation. Content is absolutely positioned with its
// natural centre anchored at (50%, 100vh) within the section — so when the
// section's bottom touches the viewport bottom (rect.top = -50vh, progress
// = 1) the natural viewport centre is already at 50vh (screen centre) with
// zero transform. Before that point slideY lifts the block up from offscreen.
function Problem() {
  const S = SIZES[useBreakpoint()];
  const sectionRef = useRef(null);
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    function onScroll() {
      const el = sectionRef.current;
      if (!el) return;
      const rect = el.getBoundingClientRect();
      const vh = window.innerHeight;
      const start = vh;
      const end = vh - rect.height;
      const raw = (start - rect.top) / (start - end);
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

  const eased = progress * progress * (3 - 2 * progress);
  const countEased = 1 - Math.pow(1 - progress, 3);
  const count = Math.round(50 * countEased);
  const slideY = (1 - eased) * -100; // vh — lifts from the viewport bottom up to centre
  const wrapperOpacity = Math.min(1, 0.1 + eased * 1.1);
  const textReveal = Math.max(0, (eased - 0.55) / 0.45);
  const textShift = (1 - textReveal) * 16;

  return (
    <section
      ref={sectionRef}
      style={{
        background: C.ink,
        color: C.bone,
        borderTop: `1px solid ${C.divider}`,
        minHeight: "150vh",
        position: "relative",
        overflow: "hidden",
      }}
    >
      <div
        style={{
          position: "absolute",
          top: "100vh",
          left: "50%",
          width: "100%",
          maxWidth: S.problemMaxW,
          textAlign: S.problemAlign,
          padding: S.problemPad,
          boxSizing: "border-box",
          transform: `translate(-50%, -50%) translate3d(0, ${slideY.toFixed(2)}vh, 0)`,
          transformOrigin: "center center",
          opacity: wrapperOpacity,
          willChange: "transform, opacity",
        }}
      >
        <div
          style={{
            fontFamily: "Inter, sans-serif",
            fontSize: S.problemEyebrow,
            fontWeight: 700,
            letterSpacing: "0.22em",
            color: C.orange,
            textTransform: "uppercase",
            marginBottom: S.problemEyebrowMB,
          }}
        >
          The problem
        </div>
        <div
          style={{
            display: "flex",
            flexDirection: S.problemInnerDir,
            alignItems: S.problemInnerAlign,
            justifyContent: S.problemInnerJustify,
            gap: S.problemNumGap,
            flexWrap: "wrap",
          }}
        >
          <span
            style={{
              fontFamily: "'Jura', sans-serif",
              fontWeight: 700,
              fontSize: S.problemNum,
              lineHeight: 0.85,
              letterSpacing: "-0.04em",
              color: C.bone,
              display: "inline-block",
            }}
          >
            {count}%
          </span>
          <h2
            style={{
              fontFamily: "Inter, sans-serif",
              fontWeight: 600,
              fontSize: S.problemH2,
              lineHeight: 1.05,
              letterSpacing: "-0.02em",
              maxWidth: S.problemH2MaxW,
              margin: 0,
              color: C.bone,
              opacity: textReveal,
              transform: `translateY(${textShift.toFixed(2)}px)`,
              willChange: "transform, opacity",
            }}
          >
            of new members quit within 6 months.
          </h2>
        </div>
        <div
          style={{
            marginTop: S.problemSourceMT,
            fontFamily: "Inter, sans-serif",
            fontSize: 14,
            color: C.fg3,
            letterSpacing: "0.04em",
            opacity: textReveal * 0.9,
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
  const S = SIZES[useBreakpoint()];
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
        padding: S.solutionPad,
        minHeight: "100vh",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        textAlign: "center",
      }}
    >
      <div style={{ maxWidth: S.solutionMaxW, margin: "0 auto" }}>
        <div
          style={{
            fontFamily: "Inter, sans-serif",
            fontSize: S.solutionEyebrow,
            fontWeight: 700,
            letterSpacing: "0.22em",
            color: C.orange,
            textTransform: "uppercase",
            marginBottom: S.solutionEyebrowMB,
          }}
        >
          Our solution
        </div>
        <h2
          style={{
            fontFamily: "Inter, sans-serif",
            fontWeight: 600,
            fontSize: S.solutionH2,
            lineHeight: 0.98,
            letterSpacing: "-0.035em",
            margin: 0,
            maxWidth: S.solutionH2MaxW,
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
  // Everything on the phone frame scales off width (reference = 340px).
  const k = width / 340;
  const outerR = Math.round(52 * k);
  const innerR = Math.round(48 * k);
  const chrome = Math.max(2, Math.round(4 * k));
  const islandTop = Math.round(10 * k);
  const islandW = Math.round(96 * k);
  const islandH = Math.round(28 * k);
  const btnOut = Math.round(6 * k);
  const btnW = Math.max(2, Math.round(3 * k));
  const btnR = Math.max(1, Math.round(2 * k));
  return (
    <div
      style={{
        width: width,
        aspectRatio: "393/852",
        // Titanium-style frame: outer chrome edge → thin black bezel → screen.
        background: "#0a0c0e",
        borderRadius: outerR,
        padding: chrome, // outer chrome ring thickness
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
          borderRadius: innerR,
          overflow: "hidden",
          position: "relative",
          boxShadow: "inset 0 0 0 1.5px rgba(0,0,0,0.9)",
        }}
      >
        {/* Dynamic Island */}
        <div
          style={{
            position: "absolute",
            top: islandTop,
            left: "50%",
            transform: "translateX(-50%)",
            width: islandW,
            height: islandH,
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
            left: -btnOut,
            top: Math.round(110 * k),
            width: btnW,
            height: Math.round(28 * k),
            background: "#8a8f96",
            borderRadius: btnR,
          }}
        />
        <div
          style={{
            position: "absolute",
            left: -btnOut,
            top: Math.round(160 * k),
            width: btnW,
            height: Math.round(56 * k),
            background: "#8a8f96",
            borderRadius: btnR,
          }}
        />
        <div
          style={{
            position: "absolute",
            left: -btnOut,
            top: Math.round(224 * k),
            width: btnW,
            height: Math.round(56 * k),
            background: "#8a8f96",
            borderRadius: btnR,
          }}
        />
        <div
          style={{
            position: "absolute",
            right: -btnOut,
            top: Math.round(180 * k),
            width: btnW,
            height: Math.round(86 * k),
            background: "#8a8f96",
            borderRadius: btnR,
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
  const S = SIZES[useBreakpoint()];
  const steps = [
    {
      n: "01",
      title: "Book a class.",
      copy: "Engagement after booking with content based on the class and skill level.",
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
      copy: "Engagement after class with personalized coach feedback and content.",
      disclaimer: "Takes 5 minutes to give feedback to a class.",
      variant: "after",
      focus: 0,
    },
    {
      n: "03",
      title: "Between classes.",
      copy: "Every part of the app keeps members engaged.",
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
      const titleH = titleRef.current ? titleRef.current.offsetHeight : 160;
      setTitleHeight(titleH);
      // Phone sits below title (paddingTop=titleH). Available height = sticky - title - small bottom margin.
      const available = window.innerHeight - S.navHeight - titleH - 48;
      const w = Math.min(S.howPhoneMax, (available * 393) / 852);
      setPhoneWidth(Math.max(200, Math.round(w)));
    }
    update();
    window.addEventListener("resize", update);
    const raf = requestAnimationFrame(update);
    return () => {
      window.removeEventListener("resize", update);
      cancelAnimationFrame(raf);
    };
  }, [S.howPhoneMax, S.navHeight]);
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
        // Asymmetric fade: when a step has scrolled ABOVE the viewport
        // centre (heading toward the sticky title) we fade faster so the
        // text doesn't linger visible behind the title. Below-centre
        // (fade-in) uses the original wider window.
        const above = c < vc;
        const windowBelow = i === 0 ? vh * 0.8 : vh * 0.5;
        const windowAbove = i === 0 ? vh * 0.32 : vh * 0.22;
        const window = above ? windowAbove : windowBelow;
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

  if (!S.howSticky) {
    // Phone: simple stacked single-column layout, no sticky pin, no scroll driver.
    return (
      <>
        <section
          id="how-it-works"
          style={{
            background: C.ink,
            color: C.bone,
            padding: S.howPad,
            scrollMarginTop: S.navHeight,
          }}
        >
          <div
            style={{
              maxWidth: S.howMaxW,
              margin: "0 auto",
              textAlign: S.howAlign,
            }}
          >
            <div
              style={{
                fontFamily: "Inter, sans-serif",
                fontSize: S.howEyebrow,
                fontWeight: 700,
                letterSpacing: "0.22em",
                color: C.orange,
                textTransform: "uppercase",
                marginBottom: S.howEyebrowMB,
              }}
            >
              How it works
            </div>
            <h2
              style={{
                fontFamily: "Inter, sans-serif",
                fontWeight: 600,
                fontSize: S.howH2,
                lineHeight: 1.05,
                letterSpacing: "-0.03em",
                margin: S.howAlign === "center" ? "0 auto 40px" : "0 0 40px",
                maxWidth: S.howH2MaxW,
                textWrap: "balance",
                color: C.bone,
              }}
            >
              Make every interaction engaging.
            </h2>
            <div style={{ display: "flex", flexDirection: "column", gap: 56 }}>
              {steps.map((s, i) => (
                <div
                  key={i}
                  style={{
                    display: "flex",
                    flexDirection: "column",
                    alignItems: S.howAlign === "center" ? "center" : "stretch",
                    gap: 24,
                  }}
                >
                  <div
                    style={{
                      fontFamily: "'Jura', sans-serif",
                      fontSize: S.howStepNum,
                      fontWeight: 700,
                      color: C.orange,
                      letterSpacing: "-0.02em",
                      lineHeight: 1,
                    }}
                  >
                    {s.n}
                  </div>
                  <h3
                    style={{
                      fontFamily: "Inter, sans-serif",
                      fontWeight: 600,
                      fontSize: S.howStepH3,
                      margin: 0,
                      letterSpacing: "-0.02em",
                      color: C.bone,
                    }}
                  >
                    {s.title}
                  </h3>
                  <p
                    style={{
                      fontFamily: "Inter, sans-serif",
                      fontSize: S.howStepCopy,
                      lineHeight: 1.5,
                      color: C.fg2,
                      margin: 0,
                      maxWidth: S.howStepCopyMaxW,
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
                        margin: 0,
                        maxWidth: S.howStepCopyMaxW,
                      }}
                    >
                      {s.disclaimer}
                    </p>
                  )}
                  <div
                    style={{
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      marginTop: 8,
                    }}
                  >
                    {s.images ? (
                      <div
                        style={{
                          display: "flex",
                          alignItems: "center",
                          gap: S.howImagesGap,
                        }}
                      >
                        {s.images.map((img, j) => (
                          <React.Fragment key={j}>
                            <PhoneMock
                              variant={img.variant}
                              focus={img.focus ?? 0}
                              width={Math.round((S.howPhoneMax * 230) / 340)}
                            />
                            {j < s.images.length - 1 && (
                              <div
                                style={{
                                  color: C.orange,
                                  fontSize: S.howArrow,
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
                        width={S.howPhoneMax}
                      />
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        </section>
        <ResultBlock />
      </>
    );
  }

  return (
    <>
      <section
        id="how-it-works"
        style={{
          background: C.ink,
          color: C.bone,
          padding: S.howPad,
          scrollMarginTop: S.navHeight,
        }}
      >
        <div
          style={{
            maxWidth: S.howMaxW,
            margin: "0 auto",
            position: "relative",
          }}
        >
          {/* Sticky + scrolling wrapper — sticky releases when this wrapper ends */}
          <div style={{ position: "relative" }}>
            {/* Single sticky group: title absolutely positioned at top so it doesn't steal height from the phone */}
            <div
              style={{
                position: "sticky",
                top: S.navHeight,
                height: `calc(100vh - ${S.navHeight}px)`,
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
                  padding: S.howTitlePad,
                  zIndex: 2,
                  textAlign: "center",
                }}
              >
                <div
                  style={{
                    fontFamily: "Inter, sans-serif",
                    fontSize: S.howEyebrow,
                    fontWeight: 700,
                    letterSpacing: "0.22em",
                    color: C.orange,
                    textTransform: "uppercase",
                    marginBottom: S.howEyebrowMB,
                  }}
                >
                  Constant Engagement
                </div>
                <h2
                  style={{
                    fontFamily: "Inter, sans-serif",
                    fontWeight: 600,
                    fontSize: S.howH2,
                    lineHeight: 1,
                    letterSpacing: "-0.03em",
                    margin: "0 auto",
                    maxWidth: S.howH2MaxW,
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
                  gridTemplateColumns: S.howGrid,
                  gridTemplateRows: "1fr",
                  gap: S.howGridGap,
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
                                gap: S.howImagesGap,
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
                                        fontSize: S.howArrow,
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
                paddingLeft: S.howStepPadLeft,
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
                      fontSize: S.howStepNum,
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
                      fontSize: S.howStepH3,
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
                      fontSize: S.howStepCopy,
                      lineHeight: 1.5,
                      color: C.fg2,
                      margin: "20px 0 0",
                      maxWidth: S.howStepCopyMaxW,
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
                        maxWidth: S.howStepCopyMaxW,
                      }}
                    >
                      {s.disclaimer}
                    </p>
                  )}
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>
      <ResultBlock />
    </>
  );
}

// ---------- The Result block (shared by HowItWorks layouts) ----------
// Top-right slide-in: the section is taller than the viewport so there's
// scroll room. When the section's top edge enters the viewport the text
// starts offscreen to the top-right, then slides down-and-left into its
// resting center position as the user scrolls. Once it lands, the transform
// clamps so the text scrolls away naturally with the page.
//
// The animated variant only runs when the preceding LoopSequence is pinned
// (desktop). On tablet/phone the loop is a normal scroll, so the result is
// rendered as a plain static block at natural content height.
function ResultBlock() {
  const S = SIZES[useBreakpoint()];
  if (!S.loopPinned) return <StaticResult S={S} />;
  return <AnimatedResult S={S} />;
}

function StaticResult({ S }) {
  const headingSize = Math.round((S.solutionH2 || 72) * 0.7);
  return (
    <div
      style={{
        background: C.ink,
        padding: S.loyaltyPad || "96px 24px",
      }}
    >
      <div
        style={{
          maxWidth: S.solutionH2MaxW || 1100,
          margin: "0 auto",
          textAlign: "center",
        }}
      >
        <div
          style={{
            fontFamily: "Inter, sans-serif",
            fontSize: S.solutionEyebrow || 18,
            fontWeight: 700,
            letterSpacing: "0.22em",
            color: C.orange,
            textTransform: "uppercase",
            marginBottom: S.solutionEyebrowMB || 16,
          }}
        >
          The Result
        </div>
        <h2
          style={{
            fontFamily: "Inter, sans-serif",
            fontWeight: 600,
            fontSize: headingSize,
            lineHeight: 0.98,
            letterSpacing: "-0.035em",
            margin: 0,
            color: C.bone,
            textWrap: "balance",
          }}
        >
          Members keep thinking about{" "}
          <span style={{ color: C.orange }}>your </span>gym.
        </h2>
      </div>
    </div>
  );
}

// Scroll length (in vh) reserved for the result slide-in. Everything else
// — the content's anchor position and the starting slide offset — is
// derived from this, so tweaking the feel is a one-line change.
const RESULT_SECTION_VH = 75;
// Content center anchor within the section, measured from section top.
// Half of the section height so content sits at the section's visual
// midpoint when it comes to rest.
const RESULT_ANCHOR_VH = RESULT_SECTION_VH / 2;
// Starting vertical slide offset so content enters from the viewport
// bottom at progress=0 (before smoothstep easing pulls it up to rest).
const RESULT_SLIDE_Y_VH = -RESULT_ANCHOR_VH;

function AnimatedResult({ S }) {
  const wrapRef = useRef(null);
  const contentRef = useRef(null);
  const [progress, setProgress] = useState(0);
  useEffect(() => {
    function onScroll() {
      const el = wrapRef.current;
      if (!el) return;
      const rect = el.getBoundingClientRect();
      const vh = window.innerHeight;
      // Progress from the section top touching the viewport bottom (0) to
      // the section bottom touching the viewport bottom (1) — i.e. the
      // animation plays exactly while the section is filling the screen
      // from the bottom up.
      const start = vh;
      const end = vh - rect.height;
      const raw = (start - rect.top) / (start - end);
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
  // Compress the scroll range so the slide-in finishes early — animation
  // reaches its rest state at 60% of the section's scroll, then the title
  // sits still while the user scrolls the remaining 40%.
  const compressed = Math.min(1, progress / 0.8);
  // Smoothstep easing — symmetric ease-in-out for a clean linear-feeling glide.
  const eased = compressed * compressed * (3 - 2 * compressed);
  // Slide from the bottom-right of the viewport to the centre. Anchor and
  // slide values come from the RESULT_* constants above so the whole
  // animation scales from a single knob.
  const slideX = (1 - eased) * 55; // vw
  const slideY = (1 - eased) * RESULT_SLIDE_Y_VH; // vh
  const rot = (1 - eased) * 6;
  const opacity = Math.min(1, 0.1 + eased * 1.1);
  const headingSize = Math.round((S.solutionH2 || 72) * 0.7);
  return (
    <div
      ref={wrapRef}
      style={{
        minHeight: `${RESULT_SECTION_VH}vh`,
        background: C.ink,
        position: "relative",
        overflow: "hidden",
      }}
    >
      <div
        ref={contentRef}
        style={{
          position: "absolute",
          top: `${RESULT_ANCHOR_VH}vh`,
          left: "50%",
          width: "100%",
          maxWidth: S.solutionH2MaxW || 1100,
          textAlign: "center",
          // Horizontal padding lives on the inner wrapper (not the outer
          // section) so the slide-in animation still uses the full
          // viewport width without clipping from side padding.
          padding: "0 24px",
          boxSizing: "border-box",
          transform: `translate(-50%, -50%) translate3d(${slideX.toFixed(2)}vw, ${slideY.toFixed(2)}vh, 0) rotate(${rot.toFixed(2)}deg)`,
          transformOrigin: "center center",
          opacity,
          willChange: "transform, opacity",
        }}
      >
        <div
          style={{
            fontFamily: "Inter, sans-serif",
            fontSize: S.solutionEyebrow || 18,
            fontWeight: 700,
            letterSpacing: "0.22em",
            color: C.orange,
            textTransform: "uppercase",
            marginBottom: S.solutionEyebrowMB || 16,
          }}
        >
          The Result
        </div>
        <h2
          style={{
            fontFamily: "Inter, sans-serif",
            fontWeight: 600,
            fontSize: headingSize,
            lineHeight: 0.98,
            letterSpacing: "-0.035em",
            margin: 0,
            color: C.bone,
            textWrap: "balance",
          }}
        >
          Members stay engaged with{" "}
          <span style={{ color: C.orange }}>your </span>gym.
        </h2>
      </div>
    </div>
  );
}

// ---------- 06 · Profitable Loyalty (paper) ----------
function Loyalty() {
  const bp = useBreakpoint();
  // Mirror LoopSequence's tablet override so the section wrapper keeps its
  // `overflow: visible` (sticky-friendly) mode instead of clipping.
  const base = SIZES[bp];
  const S =
    bp === "tablet"
      ? {
          ...base,
          loopPinned: true,
          loyaltyPad: "120px 0 140px",
          loyaltyMaxW: "100%",
        }
      : base;
  return (
    <>
      <section
        style={{
          background: C.paper,
          color: C.paperInk,
          padding: S.loyaltyPad,
          // overflow:hidden breaks position:sticky used by the pinned variant,
          // so only clip when the unpinned (vertical) layout is active.
          overflow: S.loopPinned ? "visible" : "hidden",
        }}
      >
        <div
          style={{ maxWidth: S.loyaltyMaxW, margin: "0 auto", width: "100%" }}
        >
          <LoopSequence />
        </div>
      </section>

      <DualBenefit />
    </>
  );
}

// ---------- 05 · Dual Benefit (sticky reward image right, paired statements scroll left) ----------
// Mirrors the HowItWorks sticky-scroll mechanic, flipped horizontally. The
// right side pins a single reward item (shirt, friend pass, private lesson).
// The left side scrolls through paired statements — one framing the gym's win,
// one framing the member's — so every item reads as dual value in a single view.
const DUAL_BENEFIT_LABELS = {
  eyebrow: "Keep More Members",
  headline: "Loyalty programs grows gyms.",
  member: "For loyal members",
  gym: "For the gym",
};

function DualBenefit() {
  const bp = useBreakpoint();
  // Override layout flags: tablet uses the desktop sticky-scroll layout, only
  // phone falls back to stacked — how* tokens default tablet to mobile-style.
  const base = SIZES[bp];
  // Item-name display size — bigger than the shared eyebrow scale so reward
  // names ("Free Friend pass", etc.) read as the dominant label of each block.
  const itemSize = bp === "phone" ? 18 : bp === "tablet" ? 22 : 26;
  const S =
    bp === "tablet"
      ? {
          ...base,
          howSticky: true,
          howAlign: "left",
          howGrid: "1fr 1fr",
          howGridGap: 48,
          howStepPadLeft: 32,
          howTitlePad: "32px 0 20px",
        }
      : base;
  const blocks = [
    {
      n: "01",
      item: "Free/Discounted Gym Items",
      gym: "Your gym's branded gear is walking advertisements.",
      member: "Rewards loyalty with real items from your gym.",
      src: "assets/images/FreeBranding.png",
    },
    {
      n: "02",
      item: "Free Friend Pass",
      gym: "Members willingly bring potential customers to the gym for free.",
      member: "Makes their next class more enjoyable by bringing a friend.",
      src: "assets/images/FriendPass.jpg",
    },
    {
      n: "03",
      item: "Discounted Private Training",
      gym: "Gives a taste of private training creating new repeat customers.",
      member: "Affordable one on one coach time earned from consistency.",
      src: "assets/images/Privates.webp",
    },
  ];

  const [active, setActive] = useState(0);
  const titleRef = useRef(null);
  const [titleHeight, setTitleHeight] = useState(180);
  useEffect(() => {
    function update() {
      const titleH = titleRef.current ? titleRef.current.offsetHeight : 160;
      setTitleHeight(titleH);
    }
    update();
    window.addEventListener("resize", update);
    const raf = requestAnimationFrame(update);
    return () => {
      window.removeEventListener("resize", update);
      cancelAnimationFrame(raf);
    };
  }, [S.navHeight]);

  const [opacities, setOpacities] = useState(() =>
    blocks.map((_, i) => (i === 0 ? 1 : 0)),
  );
  const blockRefs = [useRef(null), useRef(null), useRef(null)];

  useEffect(() => {
    function onScroll() {
      const vh = window.innerHeight;
      const vc = vh / 2;
      const next = blockRefs.map((ref, i) => {
        const el = ref.current;
        if (!el) return 0;
        const r = el.getBoundingClientRect();
        const c = r.top + r.height / 2;
        const dist = Math.abs(c - vc);
        const above = c < vc;
        const windowBelow = i === 0 ? vh * 0.8 : vh * 0.5;
        const windowAbove = i === 0 ? vh * 0.32 : vh * 0.22;
        const w = above ? windowAbove : windowBelow;
        const t = Math.max(0, 1 - dist / w);
        return Math.pow(t, 0.35);
      });
      setOpacities(next);
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
        for (let i = 0; i < blockRefs.length; i++) {
          const el = blockRefs[i].current;
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

  const imageMax = S.howSticky ? 480 : S.howAlign === "center" ? 220 : 340;
  const renderImagePanel = (b) => (
    <div
      style={{
        position: "relative",
        width: "100%",
        maxWidth: imageMax,
        aspectRatio: "1 / 1",
        borderRadius: "50%",
        overflow: "hidden",
        transform: "translateZ(0)",
        backfaceVisibility: "hidden",
        isolation: "isolate",
      }}
    >
      <img
        src={b.src}
        alt=""
        style={{
          width: "100%",
          height: "100%",
          objectFit: "cover",
          display: "block",
          clipPath: "circle(50%)",
        }}
      />
    </div>
  );

  const renderPair = (label, text, S, isActive) => {
    const labelSize = 14;
    const textSize = S.howStepH3 ? Math.round(S.howStepH3 * 0.58) : 18;
    const centered = S.howAlign === "center";
    return (
      <div style={{ width: "100%" }}>
        <div
          style={{
            fontFamily: "'Jura', sans-serif",
            fontSize: labelSize,
            fontWeight: 700,
            letterSpacing: "0.28em",
            textTransform: "uppercase",
            color: isActive ? C.orange : "rgba(244,243,238,0.4)",
            transition: "color 240ms",
            display: "flex",
            alignItems: "center",
            justifyContent: centered ? "center" : "flex-start",
            gap: 12,
            lineHeight: 1,
          }}
        >
          {!centered && (
            <span
              style={{
                display: "inline-block",
                width: 24,
                height: 1.5,
                background: isActive ? C.orange : "rgba(244,243,238,0.3)",
                transition: "background 240ms",
              }}
            />
          )}
          {label}
        </div>
        <p
          style={{
            fontFamily: "Inter, sans-serif",
            fontWeight: 500,
            fontSize: textSize,
            lineHeight: 1.25,
            letterSpacing: "-0.02em",
            margin: centered ? "14px auto 0" : "14px 0 0",
            maxWidth: S.howStepCopyMaxW,
            color: isActive ? C.bone : "rgba(244,243,238,0.5)",
            transition: "color 240ms",
            textAlign: centered ? "center" : "left",
          }}
        >
          {text}
        </p>
      </div>
    );
  };

  if (!S.howSticky) {
    // Phone / tablet fallback — stacked single-column, no sticky.
    return (
      <section
        style={{
          background: C.ink,
          color: C.bone,
          padding: S.rewardsPad,
          scrollMarginTop: S.navHeight,
        }}
      >
        <div
          style={{
            maxWidth: S.rewardsMaxW,
            margin: "0 auto",
            textAlign: S.howAlign,
          }}
        >
          <div
            style={{
              fontFamily: "Inter, sans-serif",
              fontSize: S.rewardsEyebrow,
              fontWeight: 700,
              letterSpacing: "0.22em",
              color: C.orange,
              textTransform: "uppercase",
              marginBottom: S.rewardsEyebrowMB,
            }}
          >
            {DUAL_BENEFIT_LABELS.eyebrow}
          </div>
          <h2
            style={{
              fontFamily: "Inter, sans-serif",
              fontWeight: 600,
              fontSize: S.rewardsH2,
              lineHeight: 1.05,
              letterSpacing: "-0.03em",
              margin:
                S.howAlign === "center"
                  ? `0 auto ${S.rewardsH2MB}px`
                  : `0 0 ${S.rewardsH2MB}px`,
              maxWidth: S.rewardsH2MaxW,
              textWrap: "balance",
              color: C.bone,
            }}
          >
            {DUAL_BENEFIT_LABELS.headline}
          </h2>
          <div style={{ display: "flex", flexDirection: "column", gap: 72 }}>
            {blocks.map((b, i) => (
              <div
                key={i}
                style={{
                  display: "flex",
                  flexDirection: "column",
                  alignItems: S.howAlign === "center" ? "center" : "stretch",
                  gap: 24,
                  textAlign: S.howAlign,
                }}
              >
                <div
                  style={{
                    fontFamily: "'Jura', sans-serif",
                    fontSize: 12,
                    fontWeight: 700,
                    letterSpacing: "0.32em",
                    color: C.fg3,
                    textTransform: "uppercase",
                    marginBottom: 10,
                  }}
                >
                  Example {b.n}
                </div>
                <div
                  style={{
                    fontFamily: "Inter, sans-serif",
                    fontSize: itemSize,
                    fontWeight: 700,
                    letterSpacing: "0.18em",
                    color: C.bone,
                    textTransform: "uppercase",
                    lineHeight: 1.1,
                  }}
                >
                  {b.item}
                </div>
                <div
                  style={{
                    display: "flex",
                    justifyContent: "center",
                    width: "100%",
                  }}
                >
                  {renderImagePanel(b)}
                </div>
                {renderPair(DUAL_BENEFIT_LABELS.member, b.member, S, true)}
                {renderPair(DUAL_BENEFIT_LABELS.gym, b.gym, S, true)}
              </div>
            ))}
          </div>
        </div>
      </section>
    );
  }

  // Desktop — sticky image on the right, scrolling statements overlay on the left.
  return (
    <section
      style={{
        background: C.ink,
        color: C.bone,
        padding: S.rewardsPad,
        scrollMarginTop: S.navHeight,
      }}
    >
      <div
        style={{
          maxWidth: S.rewardsMaxW,
          margin: "0 auto",
          position: "relative",
        }}
      >
        <div style={{ position: "relative" }}>
          {/* Sticky group: centered title absolutely positioned, image in right grid cell */}
          <div
            style={{
              position: "sticky",
              top: S.navHeight,
              height: `calc(100vh - ${S.navHeight}px)`,
            }}
          >
            <div
              ref={titleRef}
              style={{
                position: "absolute",
                top: 0,
                left: 0,
                right: 0,
                padding: S.howTitlePad,
                zIndex: 2,
                textAlign: "center",
              }}
            >
              <div
                style={{
                  fontFamily: "Inter, sans-serif",
                  fontSize: S.howEyebrow,
                  fontWeight: 700,
                  letterSpacing: "0.22em",
                  color: C.orange,
                  textTransform: "uppercase",
                  marginBottom: S.howEyebrowMB,
                }}
              >
                {DUAL_BENEFIT_LABELS.eyebrow}
              </div>
              <h2
                style={{
                  fontFamily: "Inter, sans-serif",
                  fontWeight: 600,
                  fontSize: S.howH2,
                  lineHeight: 1,
                  letterSpacing: "-0.03em",
                  margin: "0 auto",
                  maxWidth: S.howH2MaxW,
                  textWrap: "balance",
                  color: C.bone,
                }}
              >
                {DUAL_BENEFIT_LABELS.headline}
              </h2>
            </div>
            <div
              style={{
                height: "100%",
                paddingTop: titleHeight,
                display: "grid",
                gridTemplateColumns: S.howGrid,
                gridTemplateRows: "1fr",
                gap: S.howGridGap,
                minHeight: 0,
                boxSizing: "border-box",
              }}
            >
              {/* Left cell reserved — scrolling statement blocks overlay here via negative margin */}
              <div />
              {/* Right cell — stacked image panels crossfade based on active block */}
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
                    width: "100%",
                    height: "100%",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                  }}
                >
                  {blocks.map((b, i) => {
                    const isActive = i === active;
                    return (
                      <div
                        key={i}
                        style={{
                          position: i === 0 ? "relative" : "absolute",
                          inset: i === 0 ? undefined : 0,
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "center",
                          opacity: isActive ? 1 : 0,
                          transition: "opacity 420ms ease",
                          pointerEvents: isActive ? "auto" : "none",
                        }}
                      >
                        {renderImagePanel(b)}
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>
          </div>

          {/* Scrolling statement blocks — sibling overlaid on LEFT half */}
          <div
            style={{
              marginTop: "-100vh",
              marginRight: "50%",
              paddingRight: S.howStepPadLeft,
              paddingTop: "50vh",
              paddingBottom: "30vh",
              position: "relative",
              display: "flex",
              flexDirection: "column",
            }}
          >
            {blocks.map((b, i) => (
              <div
                key={i}
                ref={blockRefs[i]}
                data-block={i}
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
                    fontSize: 13,
                    fontWeight: 700,
                    letterSpacing: "0.32em",
                    textTransform: "uppercase",
                    color:
                      active === i
                        ? "rgba(244,243,238,0.55)"
                        : "rgba(244,243,238,0.25)",
                    transition: "color 240ms",
                    marginBottom: 14,
                  }}
                >
                  Example {b.n}
                </div>
                <div
                  style={{
                    fontFamily: "Inter, sans-serif",
                    fontSize: itemSize,
                    fontWeight: 700,
                    letterSpacing: "0.10em",
                    textTransform: "uppercase",
                    color: active === i ? C.bone : "rgba(244,243,238,0.35)",
                    transition: "color 240ms",
                    lineHeight: 1.1,
                  }}
                >
                  {b.item}
                </div>
                <div
                  style={{
                    marginTop: 32,
                    display: "flex",
                    flexDirection: "column",
                    gap: 32,
                  }}
                >
                  {renderPair(
                    DUAL_BENEFIT_LABELS.member,
                    b.member,
                    S,
                    active === i,
                  )}
                  <div
                    style={{
                      height: 1,
                      background: "rgba(244,243,238,0.12)",
                      width: "60%",
                    }}
                  />
                  {renderPair(DUAL_BENEFIT_LABELS.gym, b.gym, S, active === i)}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}

// Scroll-driven loop sequence: pins while scrolling, line fills left→right,
// and each circle scales up as the active point passes over it.
function LoopSequence() {
  const bp = useBreakpoint();
  // Tablet uses the desktop pinned/horizontal layout (not the mobile stacked one),
  // scaled down a touch to fit sub-1200px viewports.
  const base = SIZES[bp];
  const S =
    bp === "tablet"
      ? {
          ...base,
          loopPinned: true,
          loopDiscrete: false,
          loopDir: "row",
          loopItemGap: 32,
          loopMaxW: "100%",
          loopPadX: 0,
          loopCircle: 130,
          loopLineTop: 65,
          loopPtsFont: 44,
          loopLabelMT: 28,
          loopPinVhPerStep: 100,
          loopFocusBump: 0.5,
        }
      : base;
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
      desc: "Creates loyal and profitable members.",
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
      if (S.loopPinned) {
        const total = rect.height - vh;
        const scrolled = Math.max(0, Math.min(total, -rect.top));
        setProgress(total > 0 ? scrolled / total : 0);
      } else {
        // Unpinned (phone): progress tracks the viewport center as it moves
        // through the element — line fills from 0 when the center hits the
        // element's top to 1 when it hits the bottom.
        const center = vh / 2;
        const scrolled = center - rect.top;
        const total = rect.height;
        setProgress(total > 0 ? Math.max(0, Math.min(1, scrolled / total)) : 0);
      }
    }
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    return () => {
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
    };
  }, [S.loopPinned]);

  const n = items.length;
  // progress points for each circle (evenly spread with padding at the ends)
  const stops = items.map((_, i) => (i + 0.5) / n);
  const vertical = S.loopDir === "column";

  const computeState = (i) => {
    if (S.loopDiscrete) {
      const activeIdx = Math.min(n - 1, Math.floor(progress * n));
      return {
        bump: i === activeIdx ? 1 : 0,
        scale: i === activeIdx ? 1.15 : 1,
        reached: i <= activeIdx,
      };
    }
    const dist = Math.abs(progress - stops[i]);
    const bump = Math.max(0, 1 - dist / (1 / n));
    return {
      bump,
      scale: 1 + (S.loopFocusBump ?? 1.0) * Math.pow(bump, 1.2),
      reached: progress >= stops[i] - 0.02,
    };
  };

  const renderCircle = (it, state) => {
    const { bump, reached } = state;
    return (
      <div
        style={{
          position: "relative",
          width: S.loopCircle,
          height: S.loopCircle,
          borderRadius: "50%",
          background: it.img ? "transparent" : "#E8E6DF",
          border: `4px solid ${reached ? C.orange : C.paperHairline}`,
          overflow: "hidden",
          transition: "border-color 180ms ease, box-shadow 180ms ease",
          boxShadow: reached ? "0 16px 44px rgba(255,108,45,0.28)" : "none",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          // Force a compositing layer so the circular border-radius clip is
          // rasterised once and scales cleanly with the parent transform —
          // without this, Chrome/Safari intermittently expose the image's
          // rectangular bounding box during the scale transition.
          transform: "translateZ(0)",
          backfaceVisibility: "hidden",
          isolation: "isolate",
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
              // Geometric circular clip on the image itself — acts as a
              // fallback when the parent's border-radius + overflow:hidden
              // clip fails during the parent's scale transition and would
              // otherwise leak the image's rectangular corners.
              clipPath: "circle(50%)",
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
                fontSize: S.loopPtsFont,
                letterSpacing: "-0.02em",
                color: bump > 0.5 ? C.bone : C.paperInk2,
                textShadow: bump > 0.5 ? "0 2px 6px rgba(0,0,0,0.18)" : "none",
                transition: "color 180ms ease, text-shadow 180ms ease",
              }}
            >
              {it.text}
            </span>
            <span
              style={{
                fontFamily: "'Jura', sans-serif",
                fontWeight: 700,
                fontSize: S.loopPtsLabelFont,
                letterSpacing: "0.24em",
                color: bump > 0.5 ? "rgba(244,243,238,0.92)" : C.paperInk3,
                marginTop: 8,
                transition: "color 180ms ease",
              }}
            >
              PTS
            </span>
          </div>
        )}
      </div>
    );
  };

  const renderPhoneRow = (it, i) => {
    const state = computeState(i);
    const { scale, reached } = state;
    return (
      <div key={i} style={{ display: "flex", alignItems: "center" }}>
        <div
          style={{ flex: 1, minWidth: 0, textAlign: "right", paddingRight: 12 }}
        >
          <div
            style={{
              fontFamily: "'Jura', sans-serif",
              fontSize: S.loopEyebrow || SECTION_EYEBROW_SIZE,
              fontWeight: 700,
              letterSpacing: "0.14em",
              color: reached ? C.orange : C.paperInk3,
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
              marginTop: 6,
            }}
          >
            {it.desc}
          </div>
        </div>
        <div
          style={{
            flex: 1,
            minWidth: 0,
            paddingLeft: 12,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            position: "relative",
            zIndex: 1,
          }}
        >
          <div
            style={{
              transform: `scale(${scale.toFixed(3)})`,
              transition: "transform 180ms linear",
            }}
          >
            {renderCircle(it, state)}
          </div>
        </div>
      </div>
    );
  };

  const renderItem = (it, i) => {
    const state = computeState(i);
    const { scale, reached } = state;
    const bump = state.bump;
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
            width: S.loopCircle,
            height: S.loopCircle,
            margin: "0 auto",
            borderRadius: "50%",
            background: it.img ? "transparent" : "#E8E6DF",
            border: `4px solid ${reached ? C.orange : C.paperHairline}`,
            overflow: "hidden",
            transition: "border-color 180ms ease, box-shadow 180ms ease",
            boxShadow: reached ? "0 16px 44px rgba(255,108,45,0.28)" : "none",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            // See renderCircle for rationale — force a composite layer so
            // the circular clip doesn't break during the parent's scale
            // transition.
            transform: "translateZ(0)",
            backfaceVisibility: "hidden",
            isolation: "isolate",
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
                  fontSize: S.loopPtsFont,
                  letterSpacing: "-0.02em",
                  color: bump > 0.5 ? C.bone : C.paperInk2,
                  textShadow:
                    bump > 0.5 ? "0 2px 6px rgba(0,0,0,0.18)" : "none",
                  transition: "color 180ms ease, text-shadow 180ms ease",
                }}
              >
                {it.text}
              </span>
              <span
                style={{
                  fontFamily: "'Jura', sans-serif",
                  fontWeight: 700,
                  fontSize: S.loopPtsLabelFont,
                  letterSpacing: "0.24em",
                  color: bump > 0.5 ? "rgba(244,243,238,0.92)" : C.paperInk3,
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
            fontSize: S.loopEyebrow || SECTION_EYEBROW_SIZE,
            fontWeight: 700,
            letterSpacing: "0.14em",
            color: reached ? C.orange : C.paperInk3,
            marginTop: S.loopLabelMT,
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
  };

  const contentPadding = `0 ${S.loopPadX}px`;
  const inner = (
    <div
      style={{
        width: "100%",
        maxWidth: S.loopMaxW,
        position: "relative",
        padding: contentPadding,
        margin: "0 auto",
        boxSizing: "border-box",
      }}
    >
      {/* Title — first in the group, disclaimer + sequence follow */}
      <div style={{ textAlign: "center", marginBottom: S.loopTitleMB }}>
        <div
          style={{
            fontFamily: "Inter, sans-serif",
            fontSize: S.howEyebrow || SECTION_EYEBROW_SIZE,
            fontWeight: 700,
            letterSpacing: "0.22em",
            color: C.orange,
            textTransform: "uppercase",
            marginBottom: S.loopEyebrowMB,
          }}
        >
          Profitable Loyalty
        </div>
        <h2
          style={{
            fontFamily: "Inter, sans-serif",
            fontWeight: 600,
            fontSize: S.loopH2,
            lineHeight: 1.02,
            letterSpacing: "-0.03em",
            margin: "0 auto",
            maxWidth: S.loopH2MaxW,
            textWrap: "balance",
          }}
        >
          Create a loyalty program.
        </h2>
      </div>
      {/* Disclaimer above the sequence */}
      <p
        style={{
          margin: `0 0 ${S.loopDisclaimerMB}px`,
          fontFamily: "Inter, sans-serif",
          fontSize: 15,
          fontStyle: "italic",
          color: C.paperInk3,
          textAlign: "center",
        }}
      >
        Points-per-class and reward tiers are fully configurable by the gym.
      </p>

      {vertical ? (
        <div style={{ position: "relative" }}>
          {/* Vertical track + fill — line sits at 75% of the row width (center of the right-half circle column) */}
          <div
            style={{
              position: "absolute",
              left: "75%",
              transform: "translateX(-50%)",
              top: S.loopLineTop,
              bottom: S.loopLineTop,
              width: 3,
              background: C.paperHairline,
              borderRadius: 999,
            }}
          />
          <div
            style={{
              position: "absolute",
              left: "75%",
              transform: "translateX(-50%)",
              top: S.loopLineTop,
              width: 3,
              height: `calc((100% - ${S.loopLineTop * 2}px) * ${progress})`,
              background: C.orange,
              borderRadius: 999,
              transition: "height 80ms linear",
            }}
          />
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              rowGap: S.loopItemGap,
            }}
          >
            {items.map(renderPhoneRow)}
          </div>
        </div>
      ) : (
        <div style={{ position: "relative" }}>
          {/* Horizontal track + fill — centered on circle row */}
          <div
            style={{
              position: "absolute",
              left: 0,
              right: 0,
              top: S.loopLineTop,
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
              top: S.loopLineTop,
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
            {items.map(renderItem)}
          </div>
        </div>
      )}
    </div>
  );

  if (!S.loopPinned) {
    return <div ref={wrapRef}>{inner}</div>;
  }
  return (
    <div
      ref={wrapRef}
      style={{ height: `${n * S.loopPinVhPerStep}vh`, position: "relative" }}
    >
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
        {inner}
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
  const S = SIZES[useBreakpoint()];
  const sectionRef = useRef(null);
  const [progress, setProgress] = useState(0);
  useEffect(() => {
    function onScroll() {
      const el = sectionRef.current;
      if (!el) return;
      const rect = el.getBoundingClientRect();
      const vh = window.innerHeight;
      // Drive progress off the section's center vs viewport center — the
      // "Why it matters" nav link uses a custom handler that scrolls the
      // section center to the viewport center, so progress=1 lands cleanly.
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
        padding: S.whyPad,
        minHeight: "100vh",
        display: "flex",
        alignItems: "center",
        scrollMarginTop: S.navHeight,
      }}
    >
      <div
        style={{
          maxWidth: S.whyMaxW,
          margin: "0 auto",
          width: "100%",
          textAlign: "center",
        }}
      >
        <h2
          style={{
            fontFamily: "Inter, sans-serif",
            fontWeight: 700,
            fontSize: S.whyH2,
            lineHeight: 1,
            letterSpacing: "-0.02em",
            margin: `0 auto ${S.whyH2MB}px`,
            maxWidth: S.whyH2MaxW,
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
            gridTemplateColumns: S.whyGrid,
            gap: S.whyGap,
            marginTop: S.whyGridMT,
          }}
        >
          {[
            [`${num1}×`, "cheaper to keep a member than acquire a new one."],
            [
              `$${num2}k`,
              "more a year from keeping 5% more members in a 100-member gym.",
            ],
          ].map(([n, t], i) => (
            <div key={i} style={{ textAlign: "center" }}>
              <div
                style={{
                  fontFamily: "'Jura', sans-serif",
                  fontWeight: 700,
                  fontSize: S.whyNum,
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
                  fontSize: S.whyStatH3,
                  margin: `${S.whyStatH3MT}px auto 0`,
                  lineHeight: 1.25,
                  letterSpacing: "-0.01em",
                  maxWidth: S.whyStatH3MaxW,
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
  const S = SIZES[useBreakpoint()];
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
    padding: S.footerInputPad,
    fontFamily: "Inter, sans-serif",
    fontSize: S.footerInputFont,
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
        scrollMarginTop: S.navHeight,
        color: C.bone,
        padding: S.footerPad,
        minHeight: "100vh",
        borderTop: `1px solid ${C.divider}`,
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
      }}
    >
      <div
        style={{
          maxWidth: S.footerMaxW,
          margin: "0 auto",
          width: "100%",
          textAlign: S.footerAlign,
        }}
      >
        <div
          style={{
            display: "grid",
            gridTemplateColumns: S.footerGrid,
            gap: S.footerGap,
            alignItems: "center",
            justifyItems:
              S.footerItemsAlign === "center" ? "center" : "stretch",
            paddingBottom: S.footerPadBottom,
            borderBottom: `1px solid ${C.divider}`,
          }}
        >
          <div style={{ width: "100%" }}>
            <h2
              style={{
                fontFamily: "Inter, sans-serif",
                fontWeight: 600,
                fontSize: S.footerH2,
                lineHeight: 0.98,
                letterSpacing: "-0.035em",
                margin: S.footerAlign === "center" ? "0 auto" : 0,
                maxWidth: S.footerH2MaxW,
                textWrap: "balance",
              }}
            >
              See it live.
              <br />
              Book a 15-min demo.
            </h2>
            <p
              style={{
                marginTop: S.footerTagMT,
                marginLeft: S.footerAlign === "center" ? "auto" : undefined,
                marginRight: S.footerAlign === "center" ? "auto" : undefined,
                fontFamily: "Inter, sans-serif",
                fontSize: S.footerTag,
                color: C.fg2,
                maxWidth: S.footerTagMaxW,
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
              gap: S.footerFormGap,
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
                padding: S.footerBtnPad,
                borderRadius: 12,
                fontFamily: "Inter, sans-serif",
                fontWeight: 600,
                fontSize: S.footerBtnFont,
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
            paddingTop: S.footerBottomPT,
            display: "flex",
            flexDirection: S.footerBottomDir,
            justifyContent:
              S.footerBottomDir === "column" ? "center" : "space-between",
            alignItems: "center",
            gap: S.footerBottomGap,
            textAlign: S.footerAlign,
            fontFamily: "Inter, sans-serif",
            fontSize: 13,
            color: C.fg3,
          }}
        >
          <a
            href="#top"
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
              style={{ height: S.footerLogoH, width: "auto", display: "block" }}
            />
          </a>
          <div>jesse@combatden.net · 832-871-2702</div>
        </div>
      </div>
    </footer>
  );
}

// ---------- FAQ ----------
function Faq() {
  const S = SIZES[useBreakpoint()];
  const items = [
    {
      q: "Do I need to migrate data?",
      a: "No payment information migration is needed. All we need is member names, emails, rank (optional), and your class schedule. Everything else stays where it is. We work alongside your current gym management software / payment processor.",
    },
    {
      q: "Can I customize the content?",
      a: "Yes — add YouTube videos of your own, and yours will be prioritized.",
    },
    {
      q: "Won't coach feedback take too long?",
      a: "We have an innovative coach feedback system. The coach speaks their feedback and the app formats it. Only takes about 5 minutes per class.",
    },
    {
      q: "Is a loyalty program actually worth it?",
      a: "Yes! It's used by the most successful companies in the world — Nike, Under Armour, Life Time Fitness, and countless more. It'll work for combat sports gyms too.",
    },
  ];
  const [open, setOpen] = useState(-1);
  return (
    <section
      id="faq"
      style={{
        background: C.ink,
        color: C.bone,
        padding: S.faqPad,
        scrollMarginTop: S.navHeight,
      }}
    >
      <div style={{ maxWidth: S.faqMaxW, margin: "0 auto" }}>
        <div
          style={{
            fontFamily: "Inter, sans-serif",
            fontSize: SECTION_EYEBROW_SIZE,
            fontWeight: 700,
            letterSpacing: "0.22em",
            color: C.orange,
            textTransform: "uppercase",
            marginBottom: S.faqEyebrowMB,
            textAlign: "center",
          }}
        >
          FAQ
        </div>
        <h2
          style={{
            fontFamily: "Inter, sans-serif",
            fontWeight: 600,
            fontSize: S.faqH2,
            lineHeight: 1,
            letterSpacing: "-0.03em",
            margin: `0 auto ${S.faqH2MB}px`,
            maxWidth: S.faqH2MaxW,
            textWrap: "balance",
            color: C.bone,
            textAlign: "center",
          }}
        >
          Questions, answered.
        </h2>

        <div
          style={{ display: "flex", flexDirection: "column", gap: S.faqGap }}
        >
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
                    padding: S.faqBtnPad,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    gap: S.faqBtnGap,
                    cursor: "pointer",
                    fontFamily: "Inter, sans-serif",
                    fontSize: S.faqQ,
                    fontWeight: 600,
                    color: C.bone,
                    letterSpacing: "-0.01em",
                  }}
                >
                  <span>{it.q}</span>
                  <span
                    style={{
                      color: C.orange,
                      fontSize: S.faqPlusFont,
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
                    maxHeight: isOpen ? 300 : 0,
                    overflow: "hidden",
                    transition: "max-height 320ms ease",
                  }}
                >
                  <p
                    style={{
                      margin: 0,
                      padding: S.faqAPad,
                      fontFamily: "Inter, sans-serif",
                      fontSize: S.faqA,
                      lineHeight: 1.55,
                      color: C.fg2,
                      maxWidth: S.faqAMaxW,
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
  useEffect(() => {
    const id = window.location.hash.slice(1);
    if (!id) return;
    requestAnimationFrame(() => {
      const el = document.getElementById(id);
      if (el) el.scrollIntoView({ behavior: "auto", block: "start" });
    });
  }, []);
  return (
    <div
      style={{
        background: C.ink,
        minHeight: "100vh",
        overflowX: "clip",
        maxWidth: "100vw",
      }}
    >
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
