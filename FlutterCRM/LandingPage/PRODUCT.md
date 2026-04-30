# Product

## Register

brand

## Users

Fighting-gym owners — independent operators of combat-sports gyms (BJJ, Muay Thai, MMA, boxing, kickboxing). Ambitious, allergic to more workload, running everything themselves or with a small staff. They already have a CRM (Mindbody, Kilo, Gymdesk, etc.) and are not looking to replace it; they are looking for retention.

The reader lands here from cold outreach or a referral, on a phone or laptop, with maybe two minutes of attention. They are evaluating whether CombatDen is worth a 15-minute demo call. Decision criterion: "is this a layer I can add without ripping out my current software, and does it actually keep members?"

The job to be done: get them from skeptical owner → booked demo. Not coaches, not members — they are characters in the story but not the audience.

## Product Purpose

LandingPage is the marketing leave-behind that sells the retention-layer thesis: "works alongside your current software, no card migration." It exists to convert qualified gym owners into booked demos. Every section answers a buyer objection — what is this, how does it work, why does it matter, what does it cost, can I trust this — and routes back to the same CTA: book a 15-minute demo.

Pre-PMF stage. One paying customer (GlobalMMA). The page is also an investor and partner artifact while we build the rest of the product.

Success looks like: a gym owner reads the hero, recognizes their own problem in literal terms ("members quit"), keeps scrolling, books the demo. Failure looks like: they confuse it for another all-in-one CRM and bounce.

## Brand Personality

Opinionated, combat-native, founder-direct.

- **Opinionated** — the page takes positions. It says what we do not do. It picks a fight with generic fitness SaaS by being unmistakably about combat sports.
- **Combat-native** — warm orange on warm-near-black, Jura display type, language from the sport ("fighters", "rank", "drills"). Not mint-teal, not "wellness", not "fitness journey". Reads like the gym smells.
- **Founder-direct** — copy with real numbers (1500pts ≈ 15 classes, 7× ROI on a $20 shirt), specific pain ("stops fighters from quitting"), no corporate hedging, no marketing-team softening. The founder's voice should come through.

Emotional goal on first viewport: recognition, then trust. The owner should feel "this person actually understands my gym" before they finish the headline.

## Anti-references

All three of the following are equally dangerous. Call them out hard. The page is at risk of drifting toward any of them under generic-design pressure.

- **Generic gym SaaS** — Mindbody, Kilo, Gymdesk marketing pages. Soft mint/teal palettes, "the all-in-one platform for fitness businesses", stock photos of smiling people on yoga mats, lifestyle imagery instead of fight imagery, friendly-corporate voice. CombatDen is not that and never reads as that.
- **AI-slop landing pages** — purple/indigo gradients, three-column icon-in-circle feature grids, the hero-metric template (big number + small label + supporting stats), centered-everything layouts, decorative blob graphics, generic "Welcome to the future of [X]" headlines, gradient text. None of these. Ever.
- **Replacement-CRM positioning** — copy or design that suggests we swap out the gym's current software. We are a layer that runs alongside. Migration is structurally blocked in this market and "replace your CRM" loses every deal at the billing step. Every section must reinforce alongside-not-instead.

## Design Principles

1. **Specific over generic.** Name the buyer's pain literally. "Stops fighters from quitting" — not "boost engagement", not "drive retention outcomes". If a sentence could appear on any fitness SaaS page, rewrite it until it could only appear on this one.

2. **Layer, not replacement.** Every section reinforces alongside-the-current-software. Visual rhythm, copy, mock UIs, and CTAs all carry this thesis. If a section reads like "switch to us", it is wrong.

3. **Show the math.** Concrete unit economics over vague claims. 1500 points ≈ 15 classes. $20 shirt = 7× ROI. Real numbers signal a founder who knows the business; round vague claims signal a marketing team that does not.

4. **Combat-native, not gym-generic.** Typography (Jura display + Inter body), palette (warm orange `#FF6C2D` on warm-near-black `#121619`), language, and imagery must read as fight gym on first viewport — not generic fitness, not generic SaaS. The "AI made that" test fails the moment the page becomes interchangeable with any wellness brand.

5. **Founder voice over marketing voice.** Direct, opinionated, allergic to corporate hedging. Copy edits go to `COPY` only (per `CLAUDE.md`) and should be readable as one person talking, not a brand voice committee.

## Accessibility & Inclusion

Best-effort, no formal WCAG commitment yet. The current build does not honor `prefers-reduced-motion` (orbital arcs, scroll-driven counter, sticky pinned sections) — this is a known gap flagged in `design_audit.md` and worth addressing in a focused pass, but not a brand-promise yet. Keep contrast strong (bone on warm ink already does this), keep tap targets ≥44px on mobile (currently failing on the desktop-nav fallback per audit), and don't ship anything that actively excludes — but no formal compliance claim until it's earned.
