# Landing page — draft copy

**Status:** DRAFT, in progress. Edit freely.
**Date started:** 2026-07-27
**Reflects:** `docs/Business/pivots/2026-07-27-11-customization-engine-is-the-company.md`

Marks used below:
- **LOCKED** — chosen by Jesse
- **PROPOSED** — written but not yet picked
- **OPEN** — a decision still to make

---

## Who this page is for

A multi-tenant white-label SaaS platform with real tenant volume. Sharpest wedge:
platforms that already run a design service, because they can read the value off a
P&L instead of imagining it.

Never sell "your tenants will love it." The vault's own research found end users do
not pay for brand depth. The gain is the platform's: deals won, and a tier that
costs a tenth of what staffing it costs.

## Copy rules in force

Business outcome first, in every element. Cut every word that doesn't change the
meaning. Say what you are, not what you're not. Result before mechanism. Talk to
"you," never open with the brand name. Concrete nouns over SaaS words. Real numbers.
No repeated words in a line or stacked across a block. No em dashes. Let the visual
carry it. Founder voice.

**Two extra filters Jesse added during drafting:**
- Don't talk about features. The page is about the design gain.
- Don't frame anything as what the platform currently lacks.

---

## Structure

1. Hero
2. What it is
3. Win more deals, pay a tenth
4. The depth
5. How it works (links to its own technical page)
6. The library
7. Closing CTA

An earlier section 8, "adopts without changing your architecture," was **cut**.
Jesse's call: there *is* an architecture change and this becomes an integral part of
their app, so claiming low friction would be dishonest. Section 5's technical page
earns the commitment instead.

---

## 1 — Hero

> # Let customers redesign your white-label app
>
> Palette, type, imagery, layout. Every screen, without a designer.
>
> `[ Book a demo ]`

- Headline: **LOCKED** (Jesse's wording)
- Subline: **LOCKED**
- CTA: **LOCKED**

**OPEN — one-word tweak:** "Let **every** customer redesign your white-label app."
Removes the ambiguity about whose customers, and puts fleet scale in the headline.
Volume is the unit of value, so the headline arguably should say volume.

**OPEN — throughput number in the hero?** "76 brands, generated in under two hours."
Leaning no now that section 6 has dropped speed language.

**Why the subline reads the way it does.** The headline has no *look* or *visual* in
it, so "redesign your app" can be read as functional, which is Gigacatalyst's
territory. The noun list closes that in the first four words. This is the same flag
the office hours session raised against the 50-character YC line.

**The hero visual** is a live rebrand: one phone, a rail of brands, instant reskin.
Design not started. It runs on `ThemeService/ThemeReact`, which already does live
re-theming across the catalog in a browser.

---

## 2 — What it is

> **The customization layer for white-label platforms.**
> Purpose-built to give every customer a branded app without a design team.

**LOCKED.**

Pattern borrowed from the gym page: a category claim, then "Purpose-built to
[result]."

---

## 3 — Win more deals, pay a tenth

> ## Win more deals. Pay a tenth of the cost.
>
> ### Win more deals.
> Walk into the pitch with their brand already in the app. The demo sells it.
>
> ### A branded app for $100 a month.
> Mighty Pro charges $1,000 for the same tier, staffed by a design team.

- Section headline: **PROPOSED**
- Beat 1 heading "Win more deals.": **LOCKED**
- Beat 1 body: **PROPOSED** (recommended of four options)
- Beat 2 heading: **PROPOSED**
- Beat 2 body: **OPEN** — see the naming decision below

### OPEN — does Mighty Pro get named?

Unnamed alternative: *"The staffed version of the same tier costs $1,000."*

The case against naming: Mighty Pro is first on the target list precisely because
they run a design service, so they're among the likeliest platforms to read this
page, and they'd be reading their own Design Lab described as the expensive way.
Cheap to change either way.

### OPEN — $100 a month per what?

Per tenant is the only reading that makes sense next to a per-customer redesign,
but it means a platform with 400 branded tenants multiplies it to $480k a year
before finishing the section. Decide whether that's the number you want them
computing unprompted.

### Why beat 1 makes no claim about buyers

Research pass on 2026-07-27 looked for data backing "customers pick the vendor
whose app can look like theirs." **There is none.** Findings worth keeping:

- **The "23% revenue from consistent branding" stat is unusable.** Demand Metric,
  2016, N=234. The survey question was "how much do you *estimate* your revenue
  would increase" — a hypothetical self-estimate. Individual answers ranged 5% to
  50%. The same publisher has since revised it down to a 10–20% range.
- **An "81% of GetApp reviewers" stat circulates and does not exist.** Direct
  fetches of the page confirm it isn't there. It appears to be a search summary
  echoing its own hallucination.
- **B2B vendor-selection surveys don't measure this.** TrustRadius, G2 and Gartner
  survey purchase criteria; per-tenant branding depth never appears. Where they
  measure "customization" they mean workflow configurability, and substituting that
  is the kind of swap a skeptical buyer catches.

So beat 1 describes a sales action instead of asserting how buyers think. Nothing
in it can be argued with.

**The opportunity in that gap:** nobody has this data, so the first party to
collect it owns it. The ten target calls are the survey. Ask each one whether
they've lost a deal where the customer wanted deeper branding than they could
give. Six yeses out of ten is a first-party number no competitor can cite, and
beat 1 gets a real second sentence.

---

## 4 — The depth

> ## Every screen becomes theirs.
> Layout, palette, type, imagery, icons, copy. Every screen in the app.

**PROPOSED.**

The visual carries this one: the same app shown as three or four apps sharing no
visual DNA. Copy stays at a heading and a line.

A third heading option was **"Nothing survives but the functionality."** It's the
most striking line available and technically the truest thing on the page, but it
front-loads a functionality claim three sections before that gets answered.

---

## 5 — How it works

> ## Assets are data. Layout is code.
>
> A pipeline generates palette, type, imagery, icons and copy. Each derives from the
> others, so they cohere.
>
> An agent rewrites the layout in your codebase. Arrangement only, so no screen
> gains or loses anything.
>
> `Read the architecture →`

**PROPOSED.**

This is the section that stops a technical reader filing the company under "another
coding agent." Deterministic where determinism exists, agentic only where it's
required, reads as architecture. One agent doing everything reads as a wrapper over
a model.

**Links to its own technical page.** Jesse's call: this is a real technical
commitment and deserves depth rather than a marketing beat.

**Functional equivalence lives on that page.** Arrangement only, no screens merged
or split, nothing added or removed, API surface provably identical, so the
customer's QA surface is unchanged by construction. It lost its home on the main
page when the old section 8 was cut. It is the strongest technical fact available
and the thing that makes the commitment acceptable to their engineering org.

---

## 6 — The library

> ## 76 brands, every screen.
> Click any one and the whole app changes.
>
> `Browse the library →`

**PROPOSED.**

No speed or generation-time language, per Jesse. This section is about browsing
examples.

**Use 76, not 80.** The docs say 80; the live catalog has 76. A visitor can count.

---

## 7 — Closing CTA

> ## See it in your customers' brands.
> Name three of them. They'll be in the app before the call ends.
>
> `[ Book a demo ]`

**PROPOSED.** Not yet worked through with Jesse.

Outcome headline over the action button. The outcome here is the demo itself,
because the live rebrand is the strongest instrument available. Telling them what
the call is pre-sells it, and "before the call ends" is the elapsed-time claim
delivered as a promise rather than a number to defend.

---

## Open decisions, collected

1. **Company and product name.** Nothing chosen. Nav, hero, footer and domain all
   need one. Structure doesn't care; final copy can't ship without it.
2. **New site, or does this replace `LandingPage/`?** The existing site sells the
   gym CRM to gym owners, which is no longer the company.
3. **Mighty Pro named or not** (section 3).
4. **$100 a month per what** (section 3).
5. **"every" in the hero headline** (section 1).
6. **Throughput number in the hero** (section 1).
7. **How the demo app is framed.** The reference app is a gym app and all 76 themes
   are fitness brands. That proves range *within* one vertical while the page claims
   any white-label app. A platform outside fitness will notice. Either lean in and
   name it as the reference implementation, or generate themes for a deliberately
   non-fitness shell first.
8. **No pricing page.** Pricing for this ICP is undefined. The $100 figure is a
   working number, not a decided price.
