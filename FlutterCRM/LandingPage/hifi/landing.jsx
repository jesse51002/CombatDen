// CombatDen — Hi-Fi landing page (Manifesto direction)
// Hero uses Orbital Arcs — concentric rotating arc segments with a soft central glow.

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

// ---------- Copy ----------
// Single source of truth for every user-visible string on the page. Edit copy
// here, never inline in JSX. Rule (also in CLAUDE.md): no hardcoded text in
// this file — anything rendered to the user lives in COPY.
const COPY = {
  brand: {
    name: "CombatDen",
    homeAria: "CombatDen home",
    contact: "jesse@combatden.net · 832-871-2702",
  },
  nav: {
    bookDemoLong: "Book a demo →",
    bookDemoShort: "Book demo",
    menuOpenAria: "Open menu",
    menuCloseAria: "Close menu",
    links: {
      howItWorks: "How it works",
      whyItMatters: "Why it matters",
      pricing: "Pricing",
      faq: "FAQ",
    },
  },
  hero: {
    eyebrow: "For combat sports gyms",
    headline: "A member app that stops fighters from quitting.",
    tagline:
      "Works alongside your current software — no card migration required.",
    cta: "Book a 15-minute demo",
  },
  howItWorks: {
    eyebrow: "Retention Booster",
    headline: "Engagement keeps members.",
    steps: [
      {
        n: "01",
        title: "Book a class.",
        copy: "Booking triggers content matched to their level. Beginners show up less nervous, and stay longer.",
      },
      {
        n: "02",
        title: "Between classes.",
        copy: "Martial arts content, rank tracking, class streaks.\nApp designed to keep members longer.",
      },
    ],
  },
  loyalty: {
    eyebrow: "Loyalty Program",
    headline: "Make loyal members.",
    blurb:
      "We enable your gym to run a loyalty program that rewards consistency, keeps members longer, and grows your gym.",
    disclaimer:
      "Points-per-class and reward tiers are fully configurable by the gym.",
    ptsLabel: "PTS",
    items: [
      { label: "Attends class", desc: "Drives attendance." },
      {
        text: "+160",
        label: "Earn points",
        desc: "Promotes class consistency.",
      },
      {
        label: "Redeem rewards",
        desc: "Creates loyal and profitable members.",
      },
    ],
    rewardsEyebrow: "Reward Examples",
    // Small uppercase label that sits above the per-slide benefit copy.
    rewardBenefitLabel: "Reward Benefit",
    rewardsPrevAria: "Previous reward",
    rewardsNextAria: "Next reward",
    // How long each slide stays in focus before the auto-advance moves on (ms).
    // Lives here so it's editable alongside the slide content, not buried in SIZES.
    rewardSlideAutoMs: 7000,
    // Rewards shown in the slideshow. Each entry now carries its own benefit
    // line — leads with why the member will love it, then closes with the
    // payoff for the gym. Image paths live inline (per request — exception
    // to the usual "image paths in a sibling array" rule).
    rewards: [
      {
        name: "Free Gym Shirt",
        cost: "1500",
        classes: "~15 classes",
        img: "assets/images/ShirtReward.webp",
        benefit:
          "Members love wearing gear from your gym and every shirt becomes a walking ad for your gym.",
      },
      {
        name: "Bring a friend to class for free",
        cost: "1000",
        classes: "~10 classes",
        img: "assets/images/FriendPass.jpg",
        benefit:
          "Members love training with their friends and every guest pass brings a new potential customer to the gym for free.",
      },
      {
        name: "Discounted Private Training",
        cost: "2500",
        classes: "~25 classes",
        img: "assets/images/Privates.webp",
        benefit:
          "Members love affordable 1-on-1 time, and it's how new high-value private training relationships start.",
      },
    ],
  },
  branded: {
    eyebrow: "Truly Yours",
    headline: "App branded for your gym.",
    body: "The app ships with your logo, colors, and gym name baked in. When members open it, they see your brand. This keeps members at your gym for longer.",
    // Real 3D-rendered phone PNG/WebP. Drop your asset at this path and it
    // appears immediately. Recommended: a transparent-background render at
    // 2x resolution (e.g. 1200×1800px) so it stays crisp on retina displays.
    phoneImg: "assets/mockups/3d_branded.png",
    phoneAlt: "Gym-branded mobile app rendered in 3D",
  },
  whyItMatters: {
    headline: "Why it matters",
    stats: [
      { suffix: "×", text: "cheaper to keep a member than acquire a new one." },
      {
        prefix: "$",
        suffix: "k",
        text: "more a year from keeping 5% more members in a 100-member gym.",
      },
    ],
  },
  faq: {
    eyebrow: "FAQ",
    headline: "Questions, answered.",
    items: [
      {
        q: "Do I need to migrate data?",
        a: "No payment information migration is needed. All we need is member names, emails, rank (optional), and your class schedule. Everything else stays where it is. We work alongside your current gym management software / payment processor.",
      },
      {
        q: "Can I customize the content?",
        a: "Yes — add YouTube videos of your own, and yours will be prioritized.",
      },
      {
        q: "Is a loyalty program actually worth it?",
        a: "Yes. The math: a retained member is $150+/mo. A $20 branded T-shirt that keeps them for one extra month is 7× ROI. That's before you factor in word-of-mouth and friend passes.",
      },
    ],
  },
  footer: {
    headlineLine1: "See it live.",
    headlineLine2: "Book a 15-min demo.",
    tagline:
      "Works alongside your current software — no card migration required.",
    placeholders: { name: "Your name", email: "Email", gym: "Gym name" },
    btnIdle: "Book a demo →",
    btnSubmitting: "Sending…",
    btnSubmitted: "✓ Thanks — Calendly opened in a new tab",
    errorMessage:
      "Couldn't record your details — but Calendly opened anyway. Feel free to book.",
  },
  glyphs: { arrow: "→", plus: "+" },
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
    navBookKey: "bookDemoLong",
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
    loopPinned: false,
    loopAutoplay: true,
    loopAutoplayPeriodMs: 11000,
    loopAutoplayHoldMs: 1500,
    loopFocusBump: 0.15,
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
    loopTitleMB: 24,
    loopBlurb: 20,
    loopBlurbMaxW: 720,
    loopBlurbMB: 40,
    loopDisclaimerMB: 56,
    loopPinVhPerStep: 100,
    loopDir: "row",
    // Reward carousel
    rewardSectionMT: 96,
    rewardSectionTitleSize: 36,
    rewardEyebrowMB: 36,
    rewardCardW: 400,
    rewardCardGap: 32,
    rewardImgR: 24,
    rewardCardPad: 28,
    rewardNameSize: 22,
    rewardCostSize: 36,
    rewardCostLabelSize: 12,
    rewardClassesSize: 13,
    rewardSideOffset: 0.62,
    rewardSideScale: 0.86,
    rewardSideOpacity: 0.32,
    rewardBenefitLabelSize: 22,
    rewardBenefitSize: 17,
    rewardBenefitMaxW: 640,
    rewardBenefitMT: 56,
    rewardBenefitLabelMB: 12,
    rewardNavBtn: 48,
    rewardNavGlyph: 22,
    rewardNavOffset: 24,
    // Branded section
    brandedPad: "160px 64px",
    brandedMaxW: 1280,
    brandedGrid: "1fr 1fr",
    brandedGap: 96,
    brandedTextOrder: 1,
    brandedPhoneOrder: 2,
    brandedEyebrow: 18,
    brandedEyebrowMB: 24,
    brandedH2: 56,
    brandedH2MaxW: 520,
    brandedH2MB: 28,
    brandedBody: 18,
    brandedBodyMaxW: 480,
    brandedPhoneW: 520,
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
    navBookKey: "bookDemoLong",

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
    loopTitleMB: 20,
    loopBlurb: 17,
    loopBlurbMaxW: 600,
    loopBlurbMB: 32,
    loopDisclaimerMB: 40,
    loopPinVhPerStep: 100,
    loopDir: "column",
    rewardSectionMT: 72,
    rewardSectionTitleSize: 28,
    rewardEyebrowMB: 28,
    rewardCardW: 300,
    rewardCardGap: 24,
    rewardImgR: 22,
    rewardCardPad: 24,
    rewardNameSize: 20,
    rewardCostSize: 32,
    rewardCostLabelSize: 12,
    rewardClassesSize: 13,
    rewardSideOffset: 0.6,
    rewardSideScale: 0.85,
    rewardSideOpacity: 0.32,
    rewardBenefitLabelSize: 18,
    rewardBenefitSize: 15,
    rewardBenefitMaxW: 540,
    rewardBenefitMT: 44,
    rewardBenefitLabelMB: 10,
    rewardNavBtn: 42,
    rewardNavGlyph: 20,
    rewardNavOffset: 16,

    brandedPad: "120px 40px",
    brandedMaxW: 1280,
    brandedGrid: "1fr 1fr",
    brandedGap: 56,
    brandedTextOrder: 1,
    brandedPhoneOrder: 2,
    brandedEyebrow: 16,
    brandedEyebrowMB: 20,
    brandedH2: 44,
    brandedH2MaxW: 420,
    brandedH2MB: 22,
    brandedBody: 17,
    brandedBodyMaxW: 420,
    brandedPhoneW: 380,

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
    navBookKey: "bookDemoShort",

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
    loopTitleMB: 16,
    loopBlurb: 15,
    loopBlurbMaxW: "100%",
    loopBlurbMB: 24,
    loopDisclaimerMB: 32,
    loopPinVhPerStep: 80,
    loopDir: "column",
    rewardSectionMT: 56,
    rewardSectionTitleSize: 22,
    rewardEyebrowMB: 22,
    rewardCardW: 200,
    rewardCardGap: 14,
    rewardImgR: 16,
    rewardCardPad: 16,
    rewardNameSize: 16,
    rewardCostSize: 24,
    rewardCostLabelSize: 10,
    rewardClassesSize: 11,
    rewardSideOffset: 0.55,
    rewardSideScale: 0.8,
    rewardSideOpacity: 0.28,
    rewardBenefitLabelSize: 15,
    rewardBenefitSize: 14,
    rewardBenefitMaxW: "100%",
    rewardBenefitMT: 32,
    rewardBenefitLabelMB: 8,
    rewardNavBtn: 36,
    rewardNavGlyph: 18,
    rewardNavOffset: 8,

    brandedPad: "80px 20px",
    brandedMaxW: "100%",
    brandedGrid: "1fr",
    brandedGap: 40,
    // Phone first on mobile so the visual sets the tone before the body copy.
    brandedTextOrder: 2,
    brandedPhoneOrder: 1,
    brandedEyebrow: 14,
    brandedEyebrowMB: 16,
    brandedH2: 32,
    brandedH2MaxW: "100%",
    brandedH2MB: 18,
    brandedBody: 16,
    brandedBodyMaxW: "100%",
    brandedPhoneW: 320,

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
  const bp = useBreakpoint();
  const S = SIZES[bp];
  const isPhone = bp === "phone";
  const [menuOpen, setMenuOpen] = useState(false);
  useEffect(() => {
    if (!isPhone && menuOpen) setMenuOpen(false);
  }, [isPhone, menuOpen]);
  useEffect(() => {
    if (!menuOpen) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = prev;
    };
  }, [menuOpen]);
  const closeMenu = () => setMenuOpen(false);
  const linkStyle = {
    color: "inherit",
    textDecoration: "none",
    cursor: "pointer",
  };
  const renderWhyClick = (e) => {
    const el = document.getElementById("why");
    if (!el) return;
    e.preventDefault();
    el.scrollIntoView({ behavior: "smooth", block: "center" });
    closeMenu();
  };
  const links = (
    <>
      <a href="#how-it-works" style={linkStyle} onClick={closeMenu}>
        {COPY.nav.links.howItWorks}
      </a>
      <a href="#why" onClick={renderWhyClick} style={linkStyle}>
        {COPY.nav.links.whyItMatters}
      </a>
      <a href="pricing.html" style={linkStyle} onClick={closeMenu}>
        {COPY.nav.links.pricing}
      </a>
      <a href="#faq" style={linkStyle} onClick={closeMenu}>
        {COPY.nav.links.faq}
      </a>
    </>
  );
  return (
    <>
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
            aria-label={COPY.brand.homeAria}
            style={{
              display: "inline-flex",
              alignItems: "center",
              lineHeight: 0,
            }}
          >
            <img
              src="assets/images/LogoTransparent.png"
              alt={COPY.brand.name}
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
              {links}
            </div>
          )}
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <a
            href="#book"
            onClick={closeMenu}
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
            {COPY.nav[S.navBookKey]}
          </a>
          {isPhone && (
            <button
              type="button"
              onClick={() => setMenuOpen((v) => !v)}
              aria-label={
                menuOpen ? COPY.nav.menuCloseAria : COPY.nav.menuOpenAria
              }
              aria-expanded={menuOpen}
              style={{
                width: 40,
                height: 40,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                background: "transparent",
                border: `1px solid ${C.divider}`,
                borderRadius: 10,
                color: C.bone,
                cursor: "pointer",
                padding: 0,
              }}
            >
              {menuOpen ? (
                <svg width="18" height="18" viewBox="0 0 20 20" fill="none" aria-hidden>
                  <path
                    d="M5 5l10 10M15 5L5 15"
                    stroke="currentColor"
                    strokeWidth="1.6"
                    strokeLinecap="round"
                  />
                </svg>
              ) : (
                <svg width="20" height="20" viewBox="0 0 20 20" fill="none" aria-hidden>
                  <path
                    d="M3 6h14M3 10h14M3 14h14"
                    stroke="currentColor"
                    strokeWidth="1.6"
                    strokeLinecap="round"
                  />
                </svg>
              )}
            </button>
          )}
        </div>
      </div>
      {/* Mobile menu — full-width dropdown panel beneath the nav. */}
      {isPhone && menuOpen && (
        <div
          style={{
            position: "fixed",
            top: S.navHeight,
            left: 0,
            right: 0,
            bottom: 0,
            zIndex: 49,
            background: "rgba(18,22,25,0.96)",
            backdropFilter: "blur(16px)",
            WebkitBackdropFilter: "blur(16px)",
            display: "flex",
            flexDirection: "column",
            padding: "24px 20px",
            gap: 20,
            fontFamily: "Inter, sans-serif",
            fontSize: 22,
            color: "rgba(244,243,238,0.85)",
          }}
        >
          {links}
        </div>
      )}
    </>
  );
}

// ---------- Hero background: Orbital Arcs ----------
// Concentric rotating arc segments + a soft orange central glow. Each arc has
// its own radius, span, rotation speed, starting offset, line width, and
// opacity — together they read as a slow, layered orbit.
const ORBITAL_ARCS = [
  { rRel: 0.18, span: 1.2, speed: 0.10, off: 0, width: 1.5, alpha: 0.55 },
  { rRel: 0.28, span: 0.8, speed: -0.08, off: 1.2, width: 1, alpha: 0.4 },
  { rRel: 0.38, span: 1.6, speed: 0.06, off: 2.4, width: 1, alpha: 0.35 },
  { rRel: 0.50, span: 0.6, speed: -0.05, off: 0.8, width: 1, alpha: 0.3 },
  { rRel: 0.64, span: 1.0, speed: 0.04, off: 3.1, width: 1, alpha: 0.22 },
  { rRel: 0.80, span: 0.5, speed: -0.03, off: 1.9, width: 1, alpha: 0.18 },
];

function HeroOrbitalArcs() {
  const canvasRef = useRef(null);
  const sizeRef = useRef({ w: 0, h: 0 });

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    function resize() {
      const parent = canvas.parentElement;
      const w = parent.clientWidth;
      const h = parent.clientHeight;
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = w * dpr;
      canvas.height = h * dpr;
      canvas.style.width = w + "px";
      canvas.style.height = h + "px";
      const ctx = canvas.getContext("2d");
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      sizeRef.current = { w, h };
    }
    resize();
    window.addEventListener("resize", resize);
    return () => window.removeEventListener("resize", resize);
  }, []);

  useRaf((t) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const { w, h } = sizeRef.current;
    if (!w || !h) return;
    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, w, h);
    const cx = w / 2;
    const cy = h / 2 + h * 0.06;
    // Radius scales with the longer viewport dim so arcs fill the space.
    const base = Math.max(w, h);

    for (const a of ORBITAL_ARCS) {
      const r = base * a.rRel;
      const start = a.off + t * a.speed * Math.PI * 2;
      const end = start + a.span;
      // Hard line.
      ctx.strokeStyle = `rgba(255,108,45,${a.alpha})`;
      ctx.lineWidth = a.width;
      ctx.beginPath();
      ctx.arc(cx, cy, r, start, end);
      ctx.stroke();
      // Soft halo behind the line for the orange-glow feel.
      ctx.strokeStyle = `rgba(255,108,45,${a.alpha * 0.2})`;
      ctx.lineWidth = a.width * 8;
      ctx.beginPath();
      ctx.arc(cx, cy, r, start, end);
      ctx.stroke();
    }
    // Central radial glow.
    const grd = ctx.createRadialGradient(cx, cy, 0, cx, cy, base * 0.18);
    grd.addColorStop(0, "rgba(255,108,45,0.25)");
    grd.addColorStop(1, "rgba(255,108,45,0)");
    ctx.fillStyle = grd;
    ctx.fillRect(0, 0, w, h);
  });

  return (
    <canvas
      ref={canvasRef}
      style={{
        position: "absolute",
        inset: 0,
        width: "100%",
        height: "100%",
        pointerEvents: "none",
      }}
    />
  );
}

// ---------- Hero (Orbital Arcs background) ----------
function Hero() {
  const S = SIZES[useBreakpoint()];
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
      {/* Orbital arcs canvas — concentric rotating arc segments. */}
      <HeroOrbitalArcs />
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
          {COPY.hero.eyebrow}
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
          {COPY.hero.headline}
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
          {COPY.hero.tagline}
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
            {COPY.hero.cta}
          </a>
        </div>
      </div>
    </section>
  );
}

// ---------- Phone mock component ----------
// Maps step variants to mockup images. `focus` (0..1) picks which vertical
// slice of the image to reveal inside the phone — 0 = top, 0.5 = middle, 1 = bottom.
const PHONE_IMAGES = {
  class: "assets/mockups/Class Screen.png",
  book: "assets/mockups/BeforeClass.png",
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
        ) : (
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
        )}
      </div>
    </div>
  );
}

// ---------- 04 · How It Works (sticky phone, text scrolls on the right) ----------
// Visual config for each HowItWorks step. Copy lives in COPY.howItWorks.steps;
// these arrays are zipped by index at render time.
const HOW_STEP_VISUALS = [
  {
    variant: "book",
    focus: 0,
    images: [
      { variant: "class", focus: 0 },
      { variant: "book", focus: 0 },
    ],
  },
  { variant: "between", focus: 0 },
];

function HowItWorks() {
  const S = SIZES[useBreakpoint()];
  const steps = COPY.howItWorks.steps.map((s, i) => ({
    ...s,
    ...HOW_STEP_VISUALS[i],
  }));

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
  const stepRefs = [useRef(null), useRef(null)];

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
              {COPY.howItWorks.eyebrow}
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
              {COPY.howItWorks.headline}
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
                                {COPY.glyphs.arrow}
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
                  {COPY.howItWorks.eyebrow}
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
                  {COPY.howItWorks.headline}
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
                                      {COPY.glyphs.arrow}
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
    </>
  );
}

// Image assets per loop item — copy lives in COPY.loyalty.items; zipped by index.
// Middle item is text-only (the +160 PTS circle), so its slot is null.
const LOYALTY_LOOP_IMAGES = [
  "assets/images/BJJClass.webp",
  null,
  "assets/images/ShirtReward.webp",
];

// Loyalty loop animation. Three steps cycle:
// attends class → earn points → redeem rewards, with a progress bar.
// Driver depends on breakpoint:
//   - Desktop (loopAutoplay=true): rAF loop fills 0→1 over loopAutoplayPeriodMs,
//     holds at 1 for loopAutoplayHoldMs, snaps back. IntersectionObserver pauses
//     off-screen and resets startTime on re-entry so the cycle plays from t=0.
//   - Tablet/phone: scroll-driven (pinned on tablet, free-scrolled on phone).
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
  const items = COPY.loyalty.items.map((it, i) => ({
    ...it,
    img: LOYALTY_LOOP_IMAGES[i] || undefined,
  }));
  const wrapRef = useRef(null);
  const [progress, setProgress] = useState(0);

  // Scroll-driven progress (mobile/tablet). Skipped when autoplay is on.
  useEffect(() => {
    if (S.loopAutoplay) return;
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
  }, [S.loopPinned, S.loopAutoplay]);

  // Autoplay rAF loop (desktop). Plays only while in view; resets on re-entry.
  useEffect(() => {
    if (!S.loopAutoplay) return;
    const el = wrapRef.current;
    if (!el) return;
    const period = S.loopAutoplayPeriodMs || 6000;
    const hold = Math.min(S.loopAutoplayHoldMs ?? 1000, period - 1);
    const fillMs = period - hold;
    let inView = false;
    let startTime = performance.now();
    let raf = 0;
    const io = new IntersectionObserver(
      (entries) => {
        const next = entries[0].isIntersecting;
        if (next && !inView) startTime = performance.now();
        inView = next;
        if (!inView) setProgress(0);
      },
      { threshold: 0 },
    );
    io.observe(el);
    function tick(now) {
      if (inView) {
        const t = (now - startTime) % period;
        setProgress(t < fillMs ? t / fillMs : 1);
      }
      raf = requestAnimationFrame(tick);
    }
    raf = requestAnimationFrame(tick);
    return () => {
      io.disconnect();
      cancelAnimationFrame(raf);
    };
  }, [S.loopAutoplay, S.loopAutoplayPeriodMs, S.loopAutoplayHoldMs]);

  const n = items.length;
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
          background: it.img ? "transparent" : "#1A1F23",
          border: `4px solid ${reached ? C.orange : C.divider}`,
          overflow: "hidden",
          transition: "border-color 180ms ease, box-shadow 180ms ease",
          boxShadow: reached ? "0 16px 44px rgba(255,108,45,0.28)" : "none",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
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
                color: bump > 0.5 ? C.bone : C.fg2,
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
                color: bump > 0.5 ? "rgba(244,243,238,0.92)" : C.fg3,
                marginTop: 8,
                transition: "color 180ms ease",
              }}
            >
              {COPY.loyalty.ptsLabel}
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
              color: reached ? C.orange : C.fg3,
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
              color: C.fg2,
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
            background: it.img ? "transparent" : "#1A1F23",
            border: `4px solid ${reached ? C.orange : C.divider}`,
            overflow: "hidden",
            transition: "border-color 180ms ease, box-shadow 180ms ease",
            boxShadow: reached ? "0 16px 44px rgba(255,108,45,0.28)" : "none",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
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
                  color: bump > 0.5 ? C.bone : C.fg2,
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
                  color: bump > 0.5 ? "rgba(244,243,238,0.92)" : C.fg3,
                  marginTop: 8,
                  transition: "color 180ms ease",
                }}
              >
                {COPY.loyalty.ptsLabel}
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
            color: reached ? C.orange : C.fg3,
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
            color: C.fg2,
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
      {/* Title — eyebrow + headline */}
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
          {COPY.loyalty.eyebrow}
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
          {COPY.loyalty.headline}
        </h2>
      </div>
      {/* Short impact blurb above the sequence — capped at loopBlurbMaxW so
          long sentences wrap cleanly instead of stretching the full row. */}
      <p
        style={{
          margin: `0 auto ${S.loopBlurbMB}px`,
          width: "100%",
          maxWidth: S.loopBlurbMaxW,
          fontFamily: "Inter, sans-serif",
          fontSize: S.loopBlurb,
          lineHeight: 1.45,
          color: C.fg2,
          textAlign: "center",
        }}
      >
        {COPY.loyalty.blurb}
      </p>

      {vertical ? (
        <div style={{ position: "relative" }}>
          {/* Vertical track + fill */}
          <div
            style={{
              position: "absolute",
              left: "75%",
              transform: "translateX(-50%)",
              top: S.loopLineTop,
              bottom: S.loopLineTop,
              width: 3,
              background: C.divider,
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
              transition: S.loopAutoplay ? "none" : "height 80ms linear",
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
          {/* Horizontal track + fill */}
          <div
            style={{
              position: "absolute",
              left: 0,
              right: 0,
              top: S.loopLineTop,
              transform: "translateY(-50%)",
              height: 3,
              background: C.divider,
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
              transition: S.loopAutoplay ? "none" : "width 80ms linear",
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

  // Autoplay/non-pinned: render inner directly. Pinned (scroll-driven on
  // tablet): wrap in a tall sticky container so the scroll progress drives
  // the loop. Autoplay desktop falls into the non-pinned branch since the
  // section already owns its 100vh canvas via the Loyalty wrapper.
  if (!S.loopPinned || S.loopAutoplay) {
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

// ---------- 06 · Profitable Loyalty (dark) ----------
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
          background: C.ink,
          color: C.bone,
          padding: S.loyaltyPad,
          // overflow:hidden breaks position:sticky used by the pinned variant,
          // so only clip when the unpinned (vertical) layout is active.
          overflow: S.loopPinned ? "visible" : "hidden",
          boxSizing: "border-box",
        }}
      >
        {/* Loop animation owns its own 100vh canvas and is centred inside it
            — that keeps it the focal point. Carousel + disclaimer flow below
            and don't compete for that vertical real estate. */}
        <div
          style={{
            minHeight: "100vh",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            boxSizing: "border-box",
          }}
        >
          <div
            style={{
              maxWidth: S.loyaltyMaxW,
              margin: "0 auto",
              width: "100%",
            }}
          >
            <LoopSequence />
          </div>
        </div>
        {/* Reward slideshow — sub-section under the 100vh. Caption underneath
            replaces the old standalone disclaimer + the removed dualBenefit copy. */}
        <RewardsSlideshow S={S} />
      </section>
    </>
  );
}

// Reward card — image-dominant, name + Jura cost, centered. Mirrors the +160
// PTS visual language from the loyalty loop circle so "earn" and "redeem" rhyme.
function RewardCard({ name, cost, classes, img, S }) {
  return (
    <div
      style={{
        flexShrink: 0,
        width: S.rewardCardW,
        // Subtle light-on-dark card — lifts the reward off the section
        // background and gives photos a clean frame to sit against.
        background: "#1A1F23",
        borderRadius: S.rewardImgR + 6,
        boxShadow: `0 1px 0 ${C.divider} inset, 0 8px 28px rgba(0,0,0,0.4)`,
        border: `1px solid ${C.divider}`,
        padding: S.rewardCardPad,
        boxSizing: "border-box",
        display: "flex",
        flexDirection: "column",
        textAlign: "center",
      }}
    >
      <div
        style={{
          width: "100%",
          aspectRatio: "1 / 1",
          borderRadius: S.rewardImgR,
          overflow: "hidden",
          background: "#0F1316",
          marginBottom: Math.round(S.rewardCardPad * 0.9),
          position: "relative",
        }}
      >
        <img
          src={img}
          alt=""
          loading="lazy"
          style={{
            width: "100%",
            height: "100%",
            objectFit: "cover",
            display: "block",
          }}
        />
      </div>
      <div
        style={{
          fontFamily: "Inter, sans-serif",
          fontWeight: 600,
          fontSize: S.rewardNameSize,
          lineHeight: 1.25,
          letterSpacing: "-0.01em",
          color: C.bone,
          marginBottom: Math.round(S.rewardCardPad * 0.45),
          textAlign: "center",
          // Two-line clamp keeps card heights uniform when names vary.
          display: "-webkit-box",
          WebkitLineClamp: 2,
          WebkitBoxOrient: "vertical",
          overflow: "hidden",
          minHeight: `${Math.round(S.rewardNameSize * 1.25 * 2)}px`,
        }}
      >
        {name}
      </div>
      <div
        style={{
          display: "flex",
          alignItems: "baseline",
          justifyContent: "center",
          gap: 6,
          marginTop: "auto",
        }}
      >
        <span
          style={{
            fontFamily: "'Jura', sans-serif",
            fontWeight: 700,
            fontSize: S.rewardCostSize,
            letterSpacing: "-0.02em",
            color: C.orange,
            lineHeight: 1,
          }}
        >
          {cost}
        </span>
        <span
          style={{
            fontFamily: "'Jura', sans-serif",
            fontWeight: 700,
            fontSize: S.rewardCostLabelSize,
            letterSpacing: "0.24em",
            color: C.fg2,
            textTransform: "uppercase",
          }}
        >
          {COPY.loyalty.ptsLabel}
        </span>
      </div>
      {classes && (
        <div
          style={{
            marginTop: Math.round(S.rewardCardPad * 0.35),
            fontFamily: "Inter, sans-serif",
            fontSize: S.rewardClassesSize,
            color: C.fg3,
            textAlign: "center",
            letterSpacing: "0.02em",
          }}
        >
          {classes}
        </div>
      )}
    </div>
  );
}

// Reward slideshow — three cards visible at once: one centered/focused,
// the other two slightly transparent and scaled down on either side.
// Auto-advances every COPY.loyalty.rewardSlideAutoMs (paused off-screen via
// IntersectionObserver), and exposes prev/next buttons. Below the slides
// sits a one-line caption that distills the dual-benefit story.
function RewardsSlideshow({ S }) {
  const wrapRef = useRef(null);
  const inViewRef = useRef(false);
  const intervalRef = useRef(null);
  const items = COPY.loyalty.rewards;
  const n = items.length;
  const [active, setActive] = useState(0);

  // Restart the auto-advance timer from zero. Called on mount and after every
  // manual prev/next click so manual interaction always gives a fresh
  // COPY.loyalty.rewardSlideAutoMs window before the next auto-advance fires.
  const restartTimer = () => {
    if (intervalRef.current) clearInterval(intervalRef.current);
    intervalRef.current = setInterval(() => {
      if (inViewRef.current) setActive((a) => (a + 1) % n);
    }, COPY.loyalty.rewardSlideAutoMs || 5000);
  };

  const goNext = () => {
    setActive((a) => (a + 1) % n);
    restartTimer();
  };
  const goPrev = () => {
    setActive((a) => (a - 1 + n) % n);
    restartTimer();
  };

  // Auto-advance, gated by visibility so we don't burn cycles off-screen.
  useEffect(() => {
    const el = wrapRef.current;
    if (!el) return;
    const io = new IntersectionObserver(
      (entries) => {
        inViewRef.current = entries[0].isIntersecting;
      },
      { threshold: 0 },
    );
    io.observe(el);
    restartTimer();
    return () => {
      io.disconnect();
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [n]);

  // Card height — kept consistent so the absolute-positioned cards have a
  // shared layout footprint. Mirrors the RewardCard box model.
  const cardH = Math.round(
    S.rewardCardW +
      S.rewardCardPad * 0.9 +
      S.rewardNameSize * 1.25 * 2 +
      S.rewardCardPad * 0.45 +
      S.rewardCostSize +
      S.rewardCardPad * 2 +
      4,
  );

  // Stage width = centre card + two side cards peeking out at sideOffset×cardW.
  const sideOffsetPx = Math.round(S.rewardCardW * S.rewardSideOffset);
  const stageW = S.rewardCardW + 2 * sideOffsetPx;
  // Add room above/below so card shadows don't clip into adjacent rows.
  const stageH = cardH + 32;

  // For each card index i, compute its slot relative to the active card:
  //   -1 = left, 0 = centre, +1 = right.
  // With n=3 every card is always in one of these three slots.
  const slotFor = (i) => {
    let r = i - active;
    if (r > n / 2) r -= n;
    if (r < -n / 2) r += n;
    return r;
  };

  return (
    <div ref={wrapRef} style={{ width: "100%", marginTop: S.rewardSectionMT }}>
      {/* Sub-section title — larger, dark, sentence-case so it doesn't fight
          with the orange "Reward Benefit" label below the slideshow. */}
      <h3
        style={{
          textAlign: "center",
          margin: `0 0 ${S.rewardEyebrowMB}px`,
          fontFamily: "Inter, sans-serif",
          fontSize: S.rewardSectionTitleSize,
          fontWeight: 600,
          letterSpacing: "-0.02em",
          color: C.bone,
        }}
      >
        {COPY.loyalty.rewardsEyebrow}
      </h3>
      <div
        style={{
          position: "relative",
          width: stageW,
          maxWidth: "100%",
          height: stageH,
          margin: "0 auto",
        }}
      >
        {items.map((it, i) => {
          const slot = slotFor(i);
          const isCentre = slot === 0;
          const tx = slot * sideOffsetPx;
          return (
            <div
              key={i}
              style={{
                position: "absolute",
                top: "50%",
                left: "50%",
                width: S.rewardCardW,
                transform: `translate(-50%, -50%) translateX(${tx}px) scale(${isCentre ? 1 : S.rewardSideScale})`,
                opacity: isCentre ? 1 : S.rewardSideOpacity,
                zIndex: isCentre ? 2 : 1,
                pointerEvents: isCentre ? "auto" : "none",
                transition:
                  "transform 520ms cubic-bezier(0.22, 0.61, 0.36, 1), opacity 420ms ease",
                willChange: "transform, opacity",
              }}
            >
              <RewardCard
                name={it.name}
                cost={it.cost}
                classes={it.classes}
                img={it.img}
                S={S}
              />
            </div>
          );
        })}
        {/* Prev / Next buttons — sit just outside the centre card on each side */}
        <button
          type="button"
          onClick={goPrev}
          aria-label={COPY.loyalty.rewardsPrevAria}
          style={{
            position: "absolute",
            top: "50%",
            left: S.rewardNavOffset,
            transform: "translateY(-50%)",
            width: S.rewardNavBtn,
            height: S.rewardNavBtn,
            borderRadius: "50%",
            border: `1px solid ${C.divider}`,
            background: "#1A1F23",
            color: C.bone,
            cursor: "pointer",
            boxShadow: "0 4px 16px rgba(0,0,0,0.4)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: S.rewardNavGlyph,
            lineHeight: 1,
            fontFamily: "'Jura', sans-serif",
            fontWeight: 700,
            zIndex: 3,
            padding: 0,
          }}
        >
          ‹
        </button>
        <button
          type="button"
          onClick={goNext}
          aria-label={COPY.loyalty.rewardsNextAria}
          style={{
            position: "absolute",
            top: "50%",
            right: S.rewardNavOffset,
            transform: "translateY(-50%)",
            width: S.rewardNavBtn,
            height: S.rewardNavBtn,
            borderRadius: "50%",
            border: `1px solid ${C.divider}`,
            background: "#1A1F23",
            color: C.bone,
            cursor: "pointer",
            boxShadow: "0 4px 16px rgba(0,0,0,0.4)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: S.rewardNavGlyph,
            lineHeight: 1,
            fontFamily: "'Jura', sans-serif",
            fontWeight: 700,
            zIndex: 3,
            padding: 0,
          }}
        >
          ›
        </button>
      </div>
      {/* Per-slide benefit copy. The label is static; the body text swaps with
          the active slide. `key={active}` triggers a fresh fade-in each change. */}
      <div
        style={{
          margin: `${S.rewardBenefitMT}px auto 0`,
          maxWidth: S.rewardBenefitMaxW,
          textAlign: "center",
        }}
      >
        <div
          style={{
            fontFamily: "Inter, sans-serif",
            fontSize: S.rewardBenefitLabelSize,
            fontWeight: 700,
            letterSpacing: "0.22em",
            color: C.orange,
            textTransform: "uppercase",
            marginBottom: S.rewardBenefitLabelMB,
          }}
        >
          {COPY.loyalty.rewardBenefitLabel}
        </div>
        <p
          key={active}
          className="reward-benefit-text"
          style={{
            margin: 0,
            fontFamily: "Inter, sans-serif",
            fontSize: S.rewardBenefitSize,
            lineHeight: 1.5,
            color: C.bone,
          }}
        >
          {items[active].benefit}
        </p>
      </div>
      <style>{`
        @keyframes reward-benefit-fade {
          from { opacity: 0; transform: translateY(4px); }
          to   { opacity: 1; transform: translateY(0); }
        }
        .reward-benefit-text {
          animation: reward-benefit-fade 360ms ease both;
        }
      `}</style>
    </div>
  );
}

// ---------- Branded (dark, split text + tilted phone) ----------
// A 2-column section (text + 3D-tilted phone mock) sitting between the
// Loyalty rewards and Why It Matters. The phone is tilted via CSS perspective
// + rotateY for a "3D rendered" feel without needing a real 3D asset.
function Branded() {
  const S = SIZES[useBreakpoint()];
  return (
    <section
      style={{
        background: C.ink,
        color: C.bone,
        padding: S.brandedPad,
        boxSizing: "border-box",
      }}
    >
      <div
        style={{
          maxWidth: S.brandedMaxW,
          margin: "0 auto",
          display: "grid",
          gridTemplateColumns: S.brandedGrid,
          gap: S.brandedGap,
          alignItems: "center",
        }}
      >
        {/* Text column */}
        <div
          style={{
            order: S.brandedTextOrder,
            display: "flex",
            flexDirection: "column",
            alignItems: S.brandedGrid === "1fr" ? "center" : "flex-start",
            textAlign: S.brandedGrid === "1fr" ? "center" : "left",
          }}
        >
          <div
            style={{
              fontFamily: "Inter, sans-serif",
              fontSize: S.brandedEyebrow,
              fontWeight: 700,
              letterSpacing: "0.22em",
              color: C.orange,
              textTransform: "uppercase",
              marginBottom: S.brandedEyebrowMB,
            }}
          >
            {COPY.branded.eyebrow}
          </div>
          <h2
            style={{
              fontFamily: "Inter, sans-serif",
              fontWeight: 600,
              fontSize: S.brandedH2,
              lineHeight: 1.05,
              letterSpacing: "-0.03em",
              margin: `0 0 ${S.brandedH2MB}px`,
              maxWidth: S.brandedH2MaxW,
              color: C.bone,
              textWrap: "balance",
            }}
          >
            {COPY.branded.headline}
          </h2>
          <p
            style={{
              fontFamily: "Inter, sans-serif",
              fontSize: S.brandedBody,
              lineHeight: 1.55,
              color: C.fg2,
              margin: 0,
              maxWidth: S.brandedBodyMaxW,
            }}
          >
            {COPY.branded.body}
          </p>
        </div>
        {/* Phone column — real 3D-rendered PNG/WebP. The render has its
            own lighting and pose baked in, so we don't add a CSS rotation
            on top. drop-shadow grounds the image against the dark section. */}
        <div
          style={{
            order: S.brandedPhoneOrder,
            display: "flex",
            justifyContent: "center",
            alignItems: "center",
          }}
        >
          <img
            src={COPY.branded.phoneImg}
            alt={COPY.branded.phoneAlt}
            style={{
              width: S.brandedPhoneW,
              maxWidth: "100%",
              height: "auto",
              display: "block",
              filter: "drop-shadow(0 40px 60px rgba(0,0,0,0.55))",
            }}
          />
        </div>
      </div>
    </section>
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
        background: C.ink,
        color: C.bone,
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
            color: C.bone,
            textTransform: "uppercase",
          }}
        >
          {COPY.whyItMatters.headline}
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
            [
              `${num1}${COPY.whyItMatters.stats[0].suffix}`,
              COPY.whyItMatters.stats[0].text,
            ],
            [
              `${COPY.whyItMatters.stats[1].prefix}${num2}${COPY.whyItMatters.stats[1].suffix}`,
              COPY.whyItMatters.stats[1].text,
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
                  color: C.bone,
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
              {COPY.footer.headlineLine1}
              <br />
              {COPY.footer.headlineLine2}
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
              {COPY.footer.tagline}
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
              placeholder={COPY.footer.placeholders.name}
              value={form.name}
              onChange={onChange("name")}
              required
            />
            <input
              style={inputStyle}
              type="email"
              placeholder={COPY.footer.placeholders.email}
              value={form.email}
              onChange={onChange("email")}
              required
            />
            <input
              style={inputStyle}
              type="text"
              placeholder={COPY.footer.placeholders.gym}
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
                ? COPY.footer.btnSubmitting
                : submitted
                  ? COPY.footer.btnSubmitted
                  : COPY.footer.btnIdle}
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
                {COPY.footer.errorMessage}
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
            aria-label={COPY.brand.homeAria}
            style={{
              display: "inline-flex",
              alignItems: "center",
              lineHeight: 0,
            }}
          >
            <img
              src="assets/images/LogoTransparent.png"
              alt={COPY.brand.name}
              style={{ height: S.footerLogoH, width: "auto", display: "block" }}
            />
          </a>
          <div>{COPY.brand.contact}</div>
        </div>
      </div>
    </footer>
  );
}

// ---------- FAQ ----------
function Faq() {
  const S = SIZES[useBreakpoint()];
  const items = COPY.faq.items;
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
          {COPY.faq.eyebrow}
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
          {COPY.faq.headline}
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
                    {COPY.glyphs.plus}
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
    const fallback = document.getElementById("seo-fallback");
    if (fallback) fallback.remove();
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
        // Global rule: \n in any COPY string renders as a line break.
        // CSS white-space is inherited, so this applies to every descendant
        // unless an element explicitly overrides (e.g. whiteSpace: "nowrap").
        whiteSpace: "pre-line",
      }}
    >
      <Nav />
      <Hero />
      <HowItWorks />
      <Loyalty />
      <Branded />
      <WhyItMatters />
      <Faq />
      <Footer />
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
