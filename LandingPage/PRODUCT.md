# Product

## Register

brand

## Users

**Primary ICP:** Premium, branding-conscious class-based gym owners. The psychographic that matters: they care how their gym looks, they pay for quality, and they think about retention.

**Beachhead:** Fighting gym owners — independent operators of BJJ, Muay Thai, MMA, boxing, kickboxing gyms. Ambitious, running everything themselves or with a small staff. They already have a CRM (Mindbody, PushPress, Kilo, Gymdesk, etc.) and are not looking to replace it. Combat sports is where the founder has cultural fluency and warm pipeline, not the ceiling of the market.

**Expanding to:** Any premium class-based gym owner — yoga, pilates, CrossFit, barre, indoor cycling, boutique studios — with the same psychographic. The product has no sport-specific functionality. The $300+ price point self-selects for the premium/branding-conscious buyer regardless of format.

The reader lands here from cold outreach, an in-person pitch, or a referral, on a phone or laptop, with maybe two minutes of attention. They are evaluating whether this is worth a 15-minute demo. Decision criterion: "Is this a layer I can add without ripping out my current software, does it actually keep members, and does the app actually look like *my* gym?"

The job to be done: get them from skeptical owner → booked demo. Not coaches, not members — they are characters in the story, not the audience.

## Product Purpose

LandingPage is the marketing artifact that sells two things together: the retention-layer thesis ("works alongside your current software") and the design thesis ("the app is actually yours — not a template with your logo on it").

It exists to convert qualified gym owners into booked demos. Every section answers a buyer objection — what is this, how does it work, why does it matter, what does it cost, can I trust this — and routes back to the same CTA: book a 15-minute demo.

**The two theses that must both land:**

1. **Retention.** "A member app that stops your members from quitting." Works alongside their CRM, no card migration. Points, ranks, personalized content, keeps members engaged between classes.

2. **Design.** "The app is actually yours." Most gym apps are the same template with a different logo. This one looks like their gym — the look, the content, the feel. The video feed knows what kind of content belongs in their gym. The design is built for their gym type.

The compound: *"Built for your gym, keeps your members."*

**Pre-PMF stage.** Selling again after prototyping the theming pipeline and agentic video feed. Both are working. iPad demo + landing page is the sales motion.

Success: a gym owner reads the hero, recognizes their problem, scrolls, books the demo. Failure: they confuse it for another all-in-one CRM and bounce, or they don't understand why this is different from a template app.

## Page structure (rebuild)

The page was rebuilt section by section (see `contents.md` for the locked copy and the rationale per section). Order:

1. **Hero** — retention loss-hook ("The app that keeps your members from quitting"); value-forward subline; small no-migration reassurance line.
2. **What it is** — one Linear-style statement: "The best member booking app. Purpose-built to keep members longer, making them more profitable and growing gyms."
3. **Branded for your gym** — "Your brand, everywhere." Immersion result first, the 75+ theme library as the hero, custom build as the tail. Has a **Browse themes** button to the live theme library.
4. **Agentic video feed** — "Video Feed for your gym." A why-the-feed-matters lead, then four owner-facing sub-sections (create → refine → add your own → it learns), each with its own visual.
5. **Contextual delivery** — "Perfectly timed content." Largely visual (booking animation → matched video pops up); copy is just header + subheader.
6. **Loyalty program** — kept from the prior build for now; slated for a leanness trim later.
7. **Why it matters** — ROI stats (5× retention-vs-acquisition; ~$9k/yr from 5% better retention at $150/mo).
8. **Footer** — value-driven CTA ("Keep more of your members") + the book-a-demo form.

**No FAQ** — dropped in the rebuild as out of step with modern landing pages. The load-bearing "no payment migration / works alongside your software" objection is folded into the Hero (and is reinforceable elsewhere) rather than living in an FAQ.

`contents.md` is the source of truth for copy decisions; `COPY` in `hifi/copy.jsx` mirrors it. The page is built from modular files under `hifi/` (tokens, theme store, copy, shared chrome, mocks, per-section files) rather than one mega-file. See `CLAUDE.md` for the structure and the `contents.md`-in-sync rule.

## Brand Personality

**Opinionated, direct, premium.**

- **Opinionated** — the page takes positions. It says what we do not do. It picks a fight with generic gym SaaS.
- **Direct** — founder voice, not marketing-team voice. Real numbers, specific pain, no hedging.
- **Premium** — the design signals that this company has taste. If the page looks like any other SaaS landing page, it has failed the most important test: proving that the product looks different.

**Visual personality:** light and product-grade, not brochure-flashy. A cool off-white ground, one confident blue (with a subtle gradient on actions), Schibsted Grotesk + DM Mono, soft layered shadows, and live device mockups that look like the real app. See `DESIGN.md` for the full system. The page is itself the proof of the design thesis: if it doesn't look like a company with taste built it, the design bet has failed at the first gate.

**Voice generalizes to class-based gyms:** copy speaks to "members" and "your gym," not "fighters," and imagery is class-agnostic. The product has no sport-specific functionality, so the copy shouldn't either, except where a pitch is explicitly to a fighting gym. The mockups can wear any gym's brand via the theme switcher, reinforcing "the app is actually yours."

Emotional goal on first viewport: recognition ("this person understands my gym"), then trust ("this looks like a real product").

## What's changed since earlier versions

- **The $1000 fully-custom concierge tier is retired.** The customization pipeline (AI-generated themes, DAG-based design engine) made custom-quality output cheap enough to offer at $300/mo through a self-serve agent. The done-for-you concierge tier is the MVP bridge; self-serve is the destination.
- **75+ AI-generated themes exist**, one per gym type, validated. The design thesis is now provable — not just a claim.
- **The agentic video feed is built.** The feed is not a content library — it's an AI agent that interviews the gym owner, generates a content specification, curates hundreds of videos against that spec, and self-improves from manual feedback. Every gym gets a different feed because every gym has a different brief.
- **Pricing is now $100 / $300 / $500 flat / Enterprise.** Updated from the old member-count or $1000-custom model.
- **ICP generalized to class-based gyms.** The fighting-gym copy is still correct for fighting-gym pitches, but the product and page should hold up for any premium class-based gym.

## Anti-references

- **Generic gym SaaS** — Mindbody, Kilo, Gymdesk marketing pages. Soft mint/teal, "all-in-one platform", stock photos of smiling yogis, lifestyle imagery, friendly-corporate voice. Not that.
- **AI-slop landing pages** — purple/indigo gradients, three-column icon grids, hero-metric templates, blob graphics, "Welcome to the future of fitness." None of these. Ever.
- **Replacement-CRM positioning** — copy that implies we swap out the gym's current software. We are a layer that runs alongside. Migration is structurally blocked in this market. Every section reinforces alongside-not-instead.
- **"Same app for everyone" language** — never say or imply that every gym gets the same thing. The whole point is that this app is *theirs*. "Same code" is an internal architecture truth that would kill the buyer's feeling of ownership if said out loud. Lead with the outcome: "your gym's app."

## Design Principles

1. **Specific over generic.** Name the buyer's pain literally. "Stops fighters from quitting" — not "boost engagement." If a sentence could appear on any fitness SaaS page, rewrite it until it could only appear on this one.
2. **Layer, not replacement.** Every section reinforces alongside-the-current-software. Visual rhythm, copy, mock UIs, and CTAs carry this thesis.
3. **Show the math.** Concrete unit economics over vague claims. 1500 points ≈ 15 classes. $20 shirt = 7× ROI.
4. **Design proves the design thesis.** The landing page is itself the best proof that this company has taste. If a prospect looks at the page and isn't impressed by how it looks, the design bet has failed at the first gate.
5. **Founder voice over marketing voice.** Direct, opinionated, allergic to corporate hedging. One person talking, not a brand voice committee.
6. **Lean copy — cut filler.** Every word earns its place. If a sentence reads the same with a word removed, remove it. Phrasing that pads length is bad on a landing page.
7. **No em dashes.** Never use em dashes in user-visible copy. Use a comma, a period, or two sentences instead.
8. **Present what we are, not what we're not.** No comparisons, no "unlike other apps," no "not a template." Comparison reads as defending; lead with the value we present. Frame customization as "built for your gym," never "customizable to your brand" (that's the logo-swap white-label pitch every incumbent makes).

## Pricing (current)

- **Starter ($100/mo)** — shared shell. Multi-tenant CombatDen app. Full retention engine (loyalty, ranks, content). Gym gets the locked theme for their gym type — one of 75+ pre-generated themes, assigned, not editable. Logo and colors on top. Entry point priced below the ~$200 CRM reflex.
- **Premium ($300/mo)** — customization. The gym's own native App Store app, customized via the agent. Done-for-you at MVP (founder runs the pipeline); self-serve agent is the destination. Freelancer-replacement ROI: a $10k–$50k custom app for $300/mo.
- **Scale ($500/mo flat)** — multi-location. Up to 3 locations. Everything in Premium.
- **Enterprise** — Quote. For scale where recommendation system cost-to-serve climbs.

## Accessibility & Inclusion

Best-effort, no formal WCAG commitment yet. The current build does not honor `prefers-reduced-motion` (the scroll-driven count-up in §7 Why, the auto-looping booking/recs and loyalty-carousel animations, and the nav blur on scroll). The old `design_audit.md` has been removed in the redesign; treat reduced-motion as a known carryover gap. Keep contrast strong, keep tap targets ≥44px on mobile, don't ship anything that actively excludes, but no formal compliance claim until earned.
