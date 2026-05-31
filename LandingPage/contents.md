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
- **Button:** "Browse themes" → links to the theme library (placeholder `#themes` until the live library URL is wired)

Structure: immersion result first, library (75+ presets) as the hero, custom build as the short tail. No comparisons / no "what we're not" framing. No em dashes.

_How it's displayed:_ centered copy + the required **Browse themes** button, above an **infinite, slowly-looping marquee** of themed app-preview cards (each a different brand). The marquee never wraps; it scrolls continuously to the side and never stops. Cards are clickable: selecting one sets the global theme, re-skinning the hero mocks.

---

## 4. Agentic video feed

**Status:** BUILT (`hifi/sections/feed.jsx`)

_What it says:_

- **Heading:** "Videos to engage"
- **Why-a-feed lead (sits in the 01 cell):** "Video feed keeps members engaged, making them stay longer."
- **Sub-sections (owner-facing — what the owner can do; each gets its own visual):**
  1. "Create a video feed with our agent."
  2. "Tell the agent what you want (and don't want)."
  3. "Add your own videos, and they get prioritized."
  4. "Remove a video once, and it keeps similar out."

Order is flexible (founder said so) — currently arranged create → refine → add your own → it learns, ending on the self-improving line as the strongest note. Owner-facing throughout. "Our agent" makes clear it's part of the product. No em dashes.

_How it's displayed:_ a big 01 feature card (copy + lead beside a real app screenshot cropped in a phone) over a row of three soft cards (02/03/04), each with its own visual (thumbs with check/x marks, prioritized uploads, a "Not this one" removal).

---

## 5. Member video recommendation (contextual delivery)

**Status:** BUILT (`hifi/sections/recs.jsx`)

_What it says:_

- **Header:** "Perfectly timed content."
- **Subheader:** "We engage members when it matters, so they stay longer. Videos are matched to class, skill level, and preferences."

Just title + subtext. Keeps the original benefit line and adds one sentence naming the contextual signals (class, skill level, preferences). The phone animation carries the timing. No third paragraph.

_How it's displayed:_ **horizontally aligned** — a copy column (header + subheader only) beside the phone, which auto-loops a booking flow (book a class → booked → the matched warm-up video pops up 30 minutes before). Stacks to one column on narrow screens.

---

## 6. Loyalty program

**Status:** BUILT (`hifi/sections/loyalty.jsx`) — kept from the prior build, slated for a leanness trim later

_What it says:_ current loyalty copy (`COPY.loyalty`):

- **Headline:** "Make loyal members."
- **Blurb:** "Create a loyalty program that rewards consistency, keeps members longer."
- **Loop:** Attends class → Earn points (+160) → Redeem rewards → Loyal member
- **Reward examples (carousel, keeps the math):** Free gym shirt, 1,500 pts (~15 classes); Bring a friend free, 1,000 pts (~10 classes); Discounted private training, 2,500 pts (~25 classes)

Founder wants to trim this later but leave it for now. Revisit for leanness in a later pass.

_How it's displayed:_ an auto-cycling 4-step points loop, then a 3-card reward carousel (focused centre card, two peeking sides, prev/next + dots, benefit caption per reward).

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
