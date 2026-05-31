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
    logoMark: 'LOGO',
    links: [
      { label: 'Home', href: 'index.html' },
      { label: 'Themes', href: '#themes' },
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
    themeLibraryUrl: '#themes',
    rail: ['tidal', 'forge', 'refrm', 'pulse', 'sunup', 'coast', 'night', 'clay'],
  },

  // §4 Agentic video feed ----------------------------------------------------
  feed: {
    heading: 'Videos to engage',
    lead: 'Video feed keeps members engaged, making them stay longer.',
    items: [
      { id: 'create', n: '01', text: 'Create a video feed with our agent.' },
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
      { key: 'shirt', name: 'Free gym shirt', cost: '1,500', classes: '~15 classes',
        benefit: 'Members love wearing gear from your gym, and every shirt becomes a walking ad for your gym.' },
      { key: 'friend', name: 'Bring a friend free', cost: '1,000', classes: '~10 classes',
        benefit: 'Members love training with friends, and every guest pass brings a new potential customer in for free.' },
      { key: 'training', name: 'Discounted private training', cost: '2,500', classes: '~25 classes',
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
      { id: 'shell',  name: 'Shared Shell',  price: '$100',  cadence: '/mo', blurb: 'Get live on a shared app.', featured: false },
      { id: 'custom', name: 'Customization', price: '$300',  cadence: '/mo', blurb: 'Your own branded app.',     featured: true },
      { id: 'multi',  name: 'Multi-Location',price: '$500',  cadence: '/mo', blurb: 'Up to 3 locations.',        featured: false },
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
