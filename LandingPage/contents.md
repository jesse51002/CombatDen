# Landing Page — Contents

The marketing source of truth for the landing page: **what** copy/content is in each section and
**how** it's displayed. It mirrors what actually renders — `COPY` in `hifi/copy.jsx` maps 1:1 to the
copy locked here. **Keep this file in sync with the live page:** whenever landing copy changes, edit
both `copy.jsx` (what renders) and this doc (the record + rationale) in the same change.

**Spine (locked 2026-05-30, built 2026-05-31):**

1. Hero
2. What it is
3. Branded for your gym
4. Agentic video feed
5. Member video recommendation (contextual delivery)
6. Loyalty program
7. Why it matters
8. Footer (book the demo)

No FAQ. The load-bearing "no migration / works alongside your software" objection is folded into the Hero (the small disclaimer under the CTA) instead.

The page is built modularly under `hifi/` (tokens, theme store, copy, shared chrome, mocks, per-section files), light/blue/Geist system. See `DESIGN.md` and `CLAUDE.md`.

---

## 1. Hero

**Status:** BUILT (`hifi/sections/hero.jsx`)

_What it says:_

- **Eyebrow:** none (dropped)
- **Headline:** "App that keeps members from quitting."
- **Subline:** "Keep members engaged with content and rewards they care about, in an app built for your gym."
- **Small disclaimer (under CTA):** "No payment migration required."
- **CTA:** "Book a 15-minute demo"

Angle: retention loss-hook in the headline; subline is value-forward (engagement + rewards first, customization second) and leads with what members get, not pain. Customization framed as "built for your gym," never "customizable to your brand." Audience: general class-based — "members" / "your gym," not "fighters."

_How it's displayed:_ centered headline + subline + CTA + disclaimer over a gradient mesh, above a trio of phone mockups (left-tilt, center, right-tilt) that bleed off and fade into §2. The phones show the active brand theme; that theme is chosen in §3 (Your brand), and the hero mocks re-skin to match.

---

## 2. What it is

**Status:** BUILT (`hifi/sections/what-it-is.jsx`)

_What it says:_

> **The best booking app.** Purpose-built to keep members longer, making them more profitable and growing gyms.

- Linear-style statement: punchy claim + "Purpose-built to [result]." All result/value, no "how" (the how gets proven in sections 3–6).
- No separate heading — the statement is the section.

_How it's displayed:_ a single centered two-tone statement (the claim in ink with a blue period, the "Purpose-built…" tail in faint ink). No heading; the statement is the section.

---

## 3. Branded for your gym

**Status:** BUILT (`hifi/sections/brand.jsx`)

_What it says:_

- **Heading:** "Your brand, everywhere."
- **Body:** "Immerse members in your brand's vibe, imagery, colors. Choose from 75+ ready-made designs, or we'll build one custom, no extra charge."
- **Button:** "Browse themes" → links to the live theme browser at `https://themes.combatden.net` (same tab)

Structure: immersion result first, library (75+ presets) as the hero, custom build as the short tail. No comparisons / no "what we're not" framing. No em dashes.

_How it's displayed:_ a split layout — copy + the required **Browse themes** button on the left, and a transparent looping video (`assets/landing/gymworld-3phones.webm`) of the member app shown across three brand themes on the right.

---

## 4. Agentic video feed

**Status:** BUILT (`hifi/sections/feed.jsx`)

_What it says:_

- **Heading:** none. The §4 heading ("Videos to engage") was removed; the section opens directly on the 01 card.
- **Why-a-feed lead (sits in the 01 cell):** "Video feed keeps members engaged, making them stay longer. Use our agent to create a feed with a few prompts."
- **Sub-sections (owner-facing — what the owner can do; each gets its own visual):**
  1. "Make a feed that engages."
  2. "Tell the agent what you want (and don't want)."
  3. "Add your own videos, and they get prioritized."
  4. "Remove a video once, and it keeps similar out."

Order is flexible (founder said so) — currently arranged make → refine → add your own → it learns, ending on the self-improving line as the strongest note. The 01 title now leads with the benefit ("Make a feed that engages"); the how (our agent, a few prompts) sits in the lead beneath it, per value-first. Owner-facing throughout. "Our agent" is named in the 01 lead and again in 02. No em dashes.

_How it's displayed:_ a big 01 feature card (copy + lead beside a looping screen-recording of the app's video feed, cropped in a phone) over a row of three soft cards (02/03/04), each with its own visual (thumbs with check/x marks, prioritized uploads, a "Not this one" removal).

The section runs on two independent clocks. The 01 card (phone + prompt bubble) is linked to the screen-recording: the clip cycles through 6 gym types (yoga, muay thai, running, bjj, barre, hyrox), 3 seconds each, and the prompt bubble ("Video feed for a ___") names the gym currently on screen. The lower 02/03/04 grids are deliberately unlinked, cycling through the same gyms on their own slower timer (each gym holds about 8 seconds) so the section does not flip everything at once. Both crossfade gently (about a 1 second fade) on change. Thumbnails are real content from the VideoService library: accepted YouTube thumbnails on the 02 and 04 cards, and class photos on the 03 "your own videos" card (so uploads read like real footage). This is a per-widget state machine local to the section, not the global brand theme.

---

## 5. Member video recommendation (contextual delivery)

**Status:** BUILT (`hifi/sections/recs.jsx`)

_What it says:_

- **Header:** "Perfectly timed content."
- **Subheader:** "We engage members when it matters, so they stay longer. Videos are matched to class, skill level, and preferences."

Just title + subtext. Keeps the original benefit line and adds one sentence naming the contextual signals (class, skill level, preferences). The phone animation carries the timing. No third paragraph.

_How it's displayed:_ **vertically stacked and center-aligned** — centered copy (header + subheader) above a centered phone that loops a real app screen-recording of the flow (book a class → the matched warm-up video surfaces before class). The phone screen is sized to the video's exact aspect ratio (1080x2340), so the clip fills the frame with no cropping.

---

## 6. Loyalty program

**Status:** BUILT (`hifi/sections/loyalty.jsx`) — kept from the prior build, slated for a leanness trim later

_What it says:_ current loyalty copy (`COPY.loyalty`):

- **Headline:** "Make loyal members."
- **Blurb:** "Create a loyalty program that rewards consistency, keeps members longer."
- **Loop:** Attends class → Earn points (+160) → Redeem rewards → Loyal member
- **Reward examples (carousel, keeps the math):** Free gym shirt, 1,500 pts (~15 classes); Bring a friend free, 1,000 pts (~10 classes); Discounted private training, 2,500 pts (~25 classes)

Founder wants to trim this later but leave it for now. Revisit for leanness in a later pass.

_How it's displayed:_ an auto-cycling 4-step points loop, then a 3-card reward carousel (focused centre card, two peeking sides, prev/next + dots, benefit caption per reward). Each reward card is led by a photo of the reward (a branded gym tee as a product shot, two training partners grappling and laughing on the mats, a 1-on-1 PT session); the line-icon remains a fallback if a reward has no image. The shirt and friend-pass images are founder-supplied (`assets/images/`), the PT image is Pexels stock.

---

## 7. Why it matters

**Status:** BUILT (`hifi/sections/why.jsx`)

_What it says:_

- **Header:** "Why it matters" (alt considered: "Retention pays.")
- **Stat 1:** "5× cheaper to keep a member than to find a new one."
- **Stat 2:** "$9,000 more a year from keeping just 5% more of a 100-member gym."

ROI assumption: ~$150/mo per member (5 members × $150 × 12 = $9,000). $150 is conservative for a premium class-based gym (suburban boutique studios average $120–180/mo, urban $200+/mo, 2026 data). Keep "show the math" principle.

_How it's displayed:_ two large numerals (5× and $9,000) that count up on scroll-into-view, each with its line below.

---

## 8. Footer (book the demo)

**Status:** BUILT (`hifi/footer.jsx`, shared with the pricing page)

_What it says:_

- **Headline:** "Keep more members." (value-driven, not action-driven)
- **CTA button:** "Book a 15-minute demo"
- **Reassurance line:** "No payment migration required."
- **Form fields:** name, email, gym name

Button states: "Sending…" while posting, then "✓ Thanks, Calendly opened in a new tab" (no em dash). Form logs to the Google Form and opens Calendly in a new tab, unchanged.

_How it's displayed:_ a single cohesive booking card holding the headline, the reassurance line, and the form (name / email / gym + submit), so the closing CTA reads as one unit rather than a floating headline above a separate card. Submits to Google Forms and opens Calendly. The nav and pricing CTAs anchor here (`#book`).

---

# AI page (`ai.html`)

A second page, linked from the nav as **AI**. The landing page sells the member app; this one sells
the agent layer to the same buyer. `COPY.ai` in `hifi/copy.jsx` maps 1:1 to the copy below, and the
same sync rule applies: change one, change both.

**Every number and example on this page is illustrative, not measured usage.** The stat cards and the
day log are mock furniture in the same sense as the phone mocks on the landing page: they show the
shape of the thing, not a customer's data.

**Spine:**

1. Hero
2. Problem statement
3. How it works (Monitor / Plan / Execute)
4. Proof (four stat cards)
5. The employee (a day, dealt as a deck)
6. Footer (the shared booking card, with its own headline)

## AI 1. Hero

**Status:** BUILT (`hifi/sections/ai-hero.jsx`)

- **Headline:** "Your gym software should be working harder than you are."
- **Subline:** "Supercharge your gym with a 24/7 AI employee."
- **CTA:** "Book a 15-minute demo", anchors to `#book`
- **Reassurance:** "No payment migration required." (the shared `GWDisclaimer`)

_How it's displayed:_ centred, on the same glow + dot-grid atmosphere as the landing hero, with a pair
of ring-forms from the motif drifting behind it. They scale away as the page starts moving.

## AI 2. Problem statement

**Status:** BUILT (`hifi/sections/ai-problem.jsx`)

- **Statement:** "Software shouldn't wait for you to do everything."
- **Body:** "CombatDen AI takes what you have and puts it on autopilot."

## AI 3. How it works

**Status:** BUILT (`hifi/sections/ai-how.jsx`)

- **Monitor:** "Watches members, compares gyms, and tracks industry."
- **Plan:** "Message at-risk members, marketing pushes, seasonal discounts."
- **Execute:** "Approve it once, and it runs on its own from there."

_How it's displayed:_ three cards, numbered 01/02/03. The numbering is information here, not
decoration: each step genuinely needs the one before it. The "nothing runs without you" trust point
lives in the Execute card rather than in a section of its own.

## AI 4. Proof

**Status:** BUILT (`hifi/sections/ai-proof.jsx`)

- **Heading:** "Four things it never stops working on."
- **Chat** — 9 requests handled this week. "Asked for last month's revenue by plan, answered in 12
  seconds." Avg response 8s, actions taken 6, reports pulled 3. Status: waiting on your next question.
- **Member** — $400 in retention saved this month. "Found 5 at-risk members, messaged each, 3 came
  back." Members flagged 12, check-ins sent 8, win-backs 3. Status: reviewing this week's attendance.
- **Competition** — 4 competitor signals caught this week. "Nearby gym posted a fall program launch,
  flagged as a seasonal trend." Promos tracked 2, posts reviewed 18, events flagged 1. Status: reading
  this week's posts.
- **Growth** — 3 campaign ideas drafted. "Slow week detected in August, drafted a 'bring a friend'
  promo." Ideas drafted 3, trends found 5, seasons planned 2. Status: drafting next month's promo.

_How it's displayed:_ a 2×2 grid of cards, each with a big accent numeral that counts up once the
section reveals, a "detected X, did Y" line, secondary figures, and a live status with a pulsing dot.
Competition deliberately covers promos, marketing and events rather than price tracking, which is
one-dimensional and rarely changes.

## AI 5. The employee

**Status:** BUILT (`hifi/sections/ai-employee.jsx`)

- **Headline:** "An employee" / "that never sleeps." (set into opposite corners)
- **Log:** 6:10 AM found 2 members training without an active plan · 7:15 AM matched a five-star
  review to a member, recommended a thank-you discount · 9:00 AM answered "who's overdue on payment"
  in 9 seconds · 11:30 AM caught a competitor's fall sale, recommended you run one too · 2:45 PM
  flagged Tuesday's 6pm class, underfilled three weeks running · 4:15 PM found 4 members overdue on
  their promotions · 6:00 PM spotted a seasonal opening for a New Year kickoff challenge · 9:20 PM
  benchmarked your pricing against gyms your size nearby · 11:50 PM compiled today's flags into
  tomorrow's summary.

_How it's displayed:_ a deck that deals one entry at a time, holding each for 3.5s (the first for
2.5s, so the idea lands fast). Two entries are legible at once, the newest in front and the previous
still readable above it, so it never demands a read-and-forget pace. Cards further back are blank
paper. Each entry carries an `@tag` in its own hue.

**Two deliberate rules here.** The log never reuses a §4 example for a shared category: a repeated
story reads as filler and a visitor skips it. And the eight tag hues are the one exception to
DESIGN.md's One-Accent Rule, because they are agent handles rather than brand.

## AI 6. Footer

**Status:** BUILT (reuses `hifi/footer.jsx`)

- **Headline:** "Supercharge your gym." (overrides the landing page's "Keep more members.")

Everything else, the form, the Google Form POST, the Calendly hand-off, the bottom bar, is the shared
component. There is only ever one booking flow.

## The motif

A scroll-driven 3D layer (`hifi/motif.js`), the page's one piece of visual identity. Three named
space curves, each a single closed tube with no ends and no joints: a closed spherical spiral, the
trefoil knot (Rolfsen 3_1), and a four-petal conical rose. One form is pinned to the viewport and
morphs between them as the page scrolls, holding each shape and changing quickly in between rather
than sitting in a half-blend. It drifts from the right margin to the left as it descends, and the
flower is fully formed by the time §5 reaches the middle of the screen.
