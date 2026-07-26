// copy.jsx — every marketing/section string on the site, in one place.
//
// This MIRRORS contents.md (the marketing source of truth). When copy changes,
// edit BOTH this file (what renders) and contents.md (the record + rationale)
// in the same change — see LandingPage/CLAUDE.md.
//
// Scope: section headlines, sublines, button labels, pricing data, reward data,
// stat lines, footer form copy. NOT in scope: illustrative micro-labels baked
// into a mock's furniture (status bar "9:41", agent demo dialogue, demo file
// names) — those live inline in their mock/visual component, where they're part
// of the picture, not the marketing copy.
//
// Exports COPY to window.

const COPY = {
  // shared chrome ------------------------------------------------------------
  nav: {
    links: [
      { label: 'Home', href: 'index.html' },
      { label: 'AI', href: 'ai.html' },
      { label: 'Themes', href: 'https://themes.combatden.net' },
      { label: 'Pricing', href: 'pricing.html' },
    ],
    cta: 'Book a demo',
  },
  cta: { demo: 'Book a 15-minute demo', demoShort: 'Book a demo' },
  disclaimer: 'No payment migration required.',

  // §1 Hero ------------------------------------------------------------------
  hero: {
    headline: 'App that keeps members from quitting.',
    subline: 'Keep members engaged with content and rewards they care about, in an app built for your gym.',
    switcherHint: 'Try a brand',
  },

  // §2 What it is ------------------------------------------------------------
  whatItIs: {
    lead: 'The best booking app',
    leadAccent: '.',
    tail: 'Purpose-built to keep members longer, making them more profitable and growing gyms.',
  },

  // §3 Branded for your gym --------------------------------------------------
  brand: {
    heading: 'Your brand, everywhere.',
    body: "Immerse members in your brand's vibe, imagery, colors. Choose from 75+ ready-made designs, or we'll build one custom, no extra charge.",
    button: 'Browse themes',
    themeLibraryUrl: 'https://themes.combatden.net',
    rail: ['tidal', 'forge', 'refrm', 'pulse', 'sunup', 'coast', 'night', 'clay'],
  },

  // §4 Agentic video feed ----------------------------------------------------
  feed: {
    lead: 'Video feed keeps members engaged, making them stay longer. Use our agent to create a feed with a few prompts.',
    items: [
      { id: 'create', n: '01', text: 'Make a feed that engages.' },
      { id: 'tell',   n: '02', text: "Tell the agent what you want (and don't want)." },
      { id: 'add',    n: '03', text: 'Add your own videos, and they get prioritized.' },
      { id: 'remove', n: '04', text: 'Remove a video once, and it keeps similar out.' },
    ],
  },

  // §5 Perfectly timed content -----------------------------------------------
  recs: {
    header: 'Perfectly timed content.',
    subheader: 'We engage members when it matters, so they stay longer. Videos are matched to class, skill level, and preferences.',
  },

  // §6 Loyalty ---------------------------------------------------------------
  loyalty: {
    heading: 'Make loyal members.',
    blurb: 'Create a loyalty program that rewards consistency, keeps members longer.',
    loop: [
      { key: 'attend', label: 'Attends class' },
      { key: 'earn',   label: 'Earn points', badge: '+160' },
      { key: 'redeem', label: 'Redeem rewards' },
      { key: 'loyal',  label: 'Loyal member', outcome: true },
    ],
    rewardsLabel: 'Reward examples',
    rewards: [
      { key: 'shirt', img: 'assets/landing/reward-shirt.jpg', name: 'Free gym shirt', cost: '1,500', classes: '~15 classes',
        benefit: 'Members love wearing gear from your gym, and every shirt becomes a walking ad for your gym.' },
      { key: 'friend', img: 'assets/landing/reward-friend.jpg', name: 'Bring a friend free', cost: '1,000', classes: '~10 classes',
        benefit: 'Members love training with friends, and every guest pass brings a new potential customer in for free.' },
      { key: 'training', img: 'assets/landing/reward-training.jpg', name: 'Discounted private training', cost: '2,500', classes: '~25 classes',
        benefit: "Members love affordable 1-on-1 time, and it's how new high-value private training relationships start." },
    ],
  },

  // §7 Why it matters --------------------------------------------------------
  why: {
    heading: 'Why it matters',
    stats: [
      { value: 5, suffix: '×', line: 'cheaper to keep a member than to find a new one.' },
      { prefix: '$', value: 9000, line: 'more a year from keeping just 5% more of a 100-member gym.' },
    ],
  },

  // Pricing page -------------------------------------------------------------
  pricing: {
    title: 'Pricing',
    compareLabel: 'Compare plans',
    mostPopular: 'Most popular',
    ctaPaid: 'Book a demo',
    ctaEnterprise: 'Contact us',
    tiers: [
      { id: 'shell',  name: 'Starter',    price: '$100',  cadence: '/mo', blurb: 'Get live on a shared app.', featured: false },
      { id: 'custom', name: 'Premium',    price: '$300',  cadence: '/mo', blurb: 'Your own branded app.',     featured: true },
      { id: 'multi',  name: 'Scale',      price: '$500',  cadence: '/mo', blurb: 'Up to 3 locations.',        featured: false },
      { id: 'ent',    name: 'Enterprise',    price: 'Custom',cadence: '',    blurb: 'For 4+ locations.',         featured: false },
    ],
    rows: [
      { label: 'Class booking', vals: [true, true, true, true] },
      { label: 'Agentic video feed', vals: [true, true, true, true] },
      { label: 'Member video recommendations', vals: [true, true, true, true] },
      { label: 'Loyalty program', sub: 'Points, rewards, streaks', vals: [true, true, true, true] },
      { label: 'Rank system', sub: 'Divisions + tier promotion', vals: [true, true, true, true] },
      { label: 'Themes', vals: ['Limited', true, true, true] },
      { label: 'Fully custom design', vals: [false, true, true, true] },
      { label: 'Your own app on the App Store', vals: [false, true, true, true] },
      { label: 'Number of locations', vals: ['1', '1', 'Up to 3', '4+'] },
    ],
  },

  // AI page (ai.html) ---------------------------------------------------------
  // Every number and example below is illustrative, not measured usage. The stat
  // cards and the day log are mock furniture in the same sense as the phone mocks
  // on the landing page: they show the shape of the thing, not a customer's data.
  ai: {
    hero: {
      headline: 'Your gym software should be working harder than you are.',
      subline: 'Supercharge your gym with a 24/7 AI employee.',
    },
    problem: {
      statement: "Software shouldn't wait for you to do everything.",
      body: 'CombatDen AI takes what you have and puts it on autopilot.',
    },
    how: {
      steps: [
        { key: 'monitor', name: 'Monitor', text: 'Watches members, compares gyms, and tracks industry.' },
        { key: 'plan', name: 'Plan', text: 'Message at-risk members, marketing pushes, seasonal discounts.' },
        { key: 'execute', name: 'Execute', text: 'Approve it once, and it runs on its own from there.' },
      ],
    },
    proof: {
      heading: 'Four things it never stops working on.',
      cards: [
        // The Chat card shows the exchange itself instead of a steps pair, so it
        // has no `steps`; its dialogue is mock furniture and lives in the component.
        { key: 'chat', tag: 'Chat', num: '9', numLabel: 'requests handled this week',
          secondary: [['Avg response', '8s'], ['Actions taken', '6'], ['Reports pulled', '3']],
          status: 'Waiting on your next question' },
        { key: 'member', tag: 'Member', num: '$400', numLabel: 'in retention saved this month',
          steps: ['Found 5 at-risk members', 'Messaged each, 3 came back'],
          secondary: [['Members flagged', '12'], ['Check-ins sent', '8'], ['Win-backs', '3']],
          status: "Reviewing this week's attendance" },
        { key: 'competition', tag: 'Competition', num: '4', numLabel: 'competitor signals caught this week',
          steps: ['Nearby gym posted a fall program launch on Instagram', 'Flagged as a seasonal trend'],
          secondary: [['Promos tracked', '2'], ['Posts reviewed', '18'], ['Events flagged', '1']],
          status: "Reading this week's posts" },
        { key: 'growth', tag: 'Growth', num: '3', numLabel: 'campaign ideas drafted',
          steps: ['Slow week detected in August', 'Drafted a "bring a friend" promo'],
          secondary: [['Ideas drafted', '3'], ['Trends found', '5'], ['Seasons planned', '2']],
          status: "Drafting next month's promo" },
      ],
    },
    // Deliberately never reuses a §4 example. A repeated story reads as filler.
    employee: {
      lede: 'An employee',
      trail: 'that never sleeps.',
      log: [
        { time: '6:10 AM', tag: 'revenue', text: 'Found 2 members training without an active plan on file.' },
        { time: '7:15 AM', tag: 'reputation', text: 'Matched a new five-star review to a member, recommended a thank-you discount.' },
        { time: '9:00 AM', tag: 'chat', text: 'Answered "who’s overdue on payment" in 9 seconds.' },
        { time: '11:30 AM', tag: 'competition', text: "Caught a competitor's fall sale, recommended you run one too." },
        { time: '2:45 PM', tag: 'schedule', text: "Flagged Tuesday's 6pm class, underfilled three weeks running." },
        { time: '4:15 PM', tag: 'member', text: 'Found 4 members overdue on their promotions.' },
        { time: '6:00 PM', tag: 'growth', text: 'Spotted a seasonal opening for a New Year kickoff challenge.' },
        { time: '9:20 PM', tag: 'industry', text: 'Benchmarked your pricing against gyms your size nearby.' },
        { time: '11:50 PM', tag: 'chat', text: "Compiled today's flags into tomorrow's summary, ready before you open the CRM." },
      ],
    },
    footerHeadline: 'Supercharge your gym.',
  },

  // §8 Footer ----------------------------------------------------------------
  footer: {
    headline: 'Keep more members.',
    reassurance: 'No payment migration required.',
    placeholders: { name: 'Your name', email: 'Email', gym: 'Gym name' },
    submit: 'Book a 15-minute demo',
    submitting: 'Sending…',
    submitted: '✓ Thanks, Calendly opened in a new tab',
    error: "Couldn't record your details, but Calendly opened anyway. Feel free to book.",
    copyright: '© 2026',
  },
};

window.COPY = COPY;
