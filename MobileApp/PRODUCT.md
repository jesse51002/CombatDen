# Product

## Register

product

## Users

Paying members of fighting gyms (BJJ, Muay Thai, MMA, kickboxing, boxing). Ages
range from teenagers to adults in their 50s. They are *already* paying the gym
through the gym's existing CRM — there is no trial, no signup funnel, and no
billing surface inside CombatDen. The member touches the app at five moments:

- **Before class** — quickly browsing or booking, often on a phone in a hurry.
- **At class** — scanning the in-gym QR with one thumb, sometimes sweaty hands,
  variable lighting on a gym floor.
- **Immediately after class** — high arousal, low patience; this is the peak
  moment where streak / points / rank / next-class prompt land.
- **24 hours later** — at a calmer moment, opening a notification with a drill
  or video tied to yesterday's class type and current rank.
- **Between classes** — light browsing of content, points balance, rank
  progress. Engagement, not work.

Mental model: the member is a *practitioner*, not a *fitness consumer*. They
already know they want to train; they don't need to be persuaded to care.

## Product Purpose

CombatDen is a member-retention layer for fighting gyms. It runs alongside the
gym's existing CRM and never touches billing, signup, check-in, or anything in
the gym's operational critical path. Its single job is to keep members thinking
about training between classes by placing a training-related touchpoint at every
moment they already interact with the gym (book → QR scan → post-class reveal →
24h follow-up → re-book).

Success looks like: members maintain longer attendance streaks, gyms reduce
churn, and the QR-scan-to-rebook loop closes faster every cycle. The loop is
the product. Anything that doesn't tighten or celebrate that loop is out of
scope.

## Brand Personality

**Data-driven athlete tooling with grit.** The app should feel like a tool a
serious practitioner uses, not a wellness companion or a fitness consumer
product. Closer to Whoop / Strava in information density and Jura-typography
seriousness than to MyFitnessPal in tone.

**Coach-to-athlete voice.** Copy is imperative and factual: "Reserve your
spot", "{count} attending", "{n}/{m} classes to {nextTier}". No
exclamation-mark inflation, no aspirational marketing prose, no second-person
hype that assumes the member needs convincing. The app talks the way a coach
updates your file, not the way an app coaches your mood.

**Post-class is the only place to be loud.** The `SparkleHero` pattern —
all-caps display copy in `big1_5`, scattered orange sparkles, hero framing —
exists *exclusively* for streak / points / rank / rewards-unlocked moments
after a class. Everywhere else (home, booking lists, profile, stats), the app
is calm, dense, and information-first. Celebration is rationed so it stays
meaningful.

Three-word personality: **disciplined, kinetic, earned.**

## Anti-references

Explicitly **not** this:

- **Generic fitness SaaS** — MyFitnessPal, Fitbod, Strava-for-everyone. No
  teal/lime pastel accents, no friendly cartoon illustrations, no mascots, no
  badges-as-stickers, no gamified-for-civilians copy ("Crush your goal!",
  "You're on fire!"). CombatDen members are already practitioners; treating
  them like beginners breaks the contract.
- **Wellness / mindfulness aesthetic** — soft gradients, pastel everything,
  rounded blobs, "self-care" copy. Wrong sport, wrong audience.
- **Gym CRM admin software** — Mindbody / ClassPass / Triib density-of-tabs
  energy. CombatDen sits next to those, but it is the member-facing layer,
  not another admin console.

Anti-cliché the existing code already avoids and must keep avoiding: the
hero-metric SaaS template (big number + tiny label + supporting stats +
gradient accent). When a metric is the focus, use `SparkleHero` (post-class
only) or `big1` / `big1_5` Jura numerals over the dark canvas — never a
gradient card.

## Design Principles

1. **The gym is dark; the app mirrors it.** Default canvas is the near-black
   `DesignConstants.backgroundColor`. Cards are subtle 10%-tint surfaces, not
   bright panels. Orange is reserved for moments of *agency* — primary CTAs,
   the in-fight metric accent, sparkle moments — never as background fill.

2. **Density + hierarchy, not whitespace.** Pack related information into
   compact rows and sections (see `ClassListItem`, `ClassMetaSection`). Use
   Jura display sizes for focal numerals and `text2nd` / `text3rd` for
   supporting details. Whitespace serves scanning, not breathing room.

3. **Post-class is celebration; in-app is clarity.** Loud, kinetic moments
   live in the post-class scaffold (`SparkleHero`, large numerals, ramped
   reveals). Everywhere else, prioritize legibility and one-thumb action over
   delight. Celebration not earned by attendance does not happen.

4. **Coach-to-athlete copy.** Imperative, factual, outcome-named. No
   exclamation marks, no "you got this!", no em dashes (per the global
   `/impeccable` ban). Match Stripe / Linear restraint, not consumer-fitness
   hype.

5. **The loop is the product.** When in doubt about a feature or screen, ask
   whether it tightens or celebrates the book → QR → reveal → re-book loop.
   If it doesn't, it doesn't ship — even if it's "cool". (See
   `docs/Business/CombatDen_Summary.md`.)

## Accessibility & Inclusion

Pragmatic for the visual-prototype phase. Do not block design iteration on
formal compliance audits, but *do* honor the realities of the use case:

- **One-thumb post-class use.** Primary CTAs sit in the bottom third on every
  screen. Tap targets ≥ 44pt where it doesn't fight the layout.
- **Variable gym lighting.** Body copy stays at `text` (warm off-white over
  near-black, ~13:1 contrast), not `text3rd`. Reserve `text3rd` for tertiary
  metadata only.
- **Member age range (teen → 50+).** Avoid `pSmall` (11pt) for anything the
  member must read to act. Use `p` (12pt) or larger for actionable copy.
- **Reduced motion.** Sparkle / reveal animations should respect a future
  reduced-motion flag when wired; for now, keep durations short (≤300ms) and
  avoid bounce/elastic curves (per the `/impeccable` ban on bounce).

When this app graduates from visual-prototype to real-data mode (see
`MobileApp/CLAUDE.md` § "What changes when this becomes real"), formalize
this section against WCAG AA targets.
