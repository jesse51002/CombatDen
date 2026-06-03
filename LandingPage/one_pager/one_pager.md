# One Pager — Contents

The marketing source of truth for the print/PDF one-pager: a single-page leave-behind handed to a
gym owner after a demo or meeting. It mirrors `../contents.md` (the landing record) in form: **what**
copy is in each block and **how** it's displayed, with the rationale. **Keep it aligned with the
landing page** — when landing copy or this sheet changes, keep both in sync.

**Implemented as `one_pager.html`** (this folder) — a static, self-contained 8.5×11in print/PDF
sheet ported from the Claude Design comp, with its screenshots under `img/`. Internal-only, never
deployed. When the copy here changes, update `one_pager.html` to match (and vice versa).

**Format:** one portrait page (8.5×11), lean density. Three heavy pillars (each with a visual) is the
ceiling on one page; everything else folds into the hero or footer. It is a static print/PDF sheet:
every visual is a still image (screenshots, a diagram, phone mockups), nothing animates. This
replaces the old pre-pivot
PDF one-pager (`CombatDen — One Pager.pdf`), which used "fighters" / "martial arts" language and had
no agentic feed or ROI.

**Spine (locked 2026-06-02):**

1. Hero
2. Videos (pillar 1)
3. Loyalty (pillar 2)
4. Branded (pillar 3)
5. Footer (book the demo)

Aligns with the landing's 8 sections, compressed: §3 brand, §4 agentic feed + §5 perfectly-timed
delivery (merged into one Videos pillar), and §6 loyalty become the three pillars. The landing's §2
positioning statement and §7 ROI are both dropped for space — the hero headline and the pillar visuals
carry the message.

**Status legend:** LOCKED (approved) · DRAFT (proposed, awaiting approval) · TODO (not drafted yet).

---

## 1. Hero

**Status:** LOCKED

_What it says:_

- **Eyebrow:** COMBATDEN
- **Headline:** "App that keeps members from quitting."
- **Disclaimer:** "No payment migration required."

No subline. Cut for space; the headline owns the promise and the pillar visuals carry the rest. The
eyebrow is kept even though the landing dropped its eyebrow, because a print leave-behind needs the
brand name up top (the old one-pager had it). Audience is general class-based per the pivot:
"members" / "your gym," never "fighters."

_How it's displayed:_ brand eyebrow at the top, large headline below, small disclaimer beneath the
headline. (Layout finalized in design.)

---

## 2. Videos (pillar 1)

**Status:** LOCKED

_What it says:_

- **Header:** "Content that retains."
- **01 Made for your gym:** "Engage members with a video feed built in a few prompts."
- **02 Perfectly timed:** "Members get content when it matters, keeping them engaged."

Merges landing §4 (agentic feed) and §5 (perfectly-timed delivery) into one pillar. The header is
pillar-specific and outcome-first: "RETENTION" alone was too broad (every pillar serves it), so it
names what *this* pillar delivers. Beat 01 is the build-it-yourself differentiator the old sheet
lacked, leading with the outcome ("Engage members…"); "a few prompts" implies the agent, so the word
"agent" is dropped. Beat 02 is the timing payoff; the "matched to class, skill, preferences" mechanic
is cut because the sell is "content when it matters," not the matching. No separate ALL-CAPS eyebrow
(the header carries it); eyebrow-or-not is decided across all three pillars together for rhythm.

_How it's displayed:_ header + the two short beats beside a phone showing a screenshot of the app's
video feed with a typed prompt bubble. The visual carries the content, so the copy stays minimal.

---

## 3. Loyalty (pillar 2)

**Status:** LOCKED

_What it says:_

- **Header:** "Make loyal members."
- **Blurb:** "Keep members longer and grow your gym with a loyalty program that rewards consistency."
- **Loop:** Attend class → Earn points +160 → Redeem rewards → Loyal member

Header is the landing §6 outcome headline. The blurb is value-first — the outcomes ("keep members
longer and grow your gym") lead, the mechanism ("a loyalty program that rewards consistency") follows;
trimmed from "by running a" to "with a." The 4-step points loop is the visual and carries the
mechanism, ending on the payoff "Loyal member"; "+160" keeps the concrete number. Reward examples
(free shirt / bring a friend / discounted PT) are dropped for space (they live on the landing §6
carousel).

_How it's displayed:_ header + blurb with the 4-step points loop (Attend class → Earn points +160 →
Redeem rewards → Loyal member), shown as a static diagram. No reward carousel.

---

## 4. Branded (pillar 3)

**Status:** LOCKED

_What it says:_

- **Header:** "Your brand, everywhere."
- **Blurb:** "Immerse members in your brand. 75+ designs, or a custom build at no extra charge."

Header and immersion line from landing §3. The "colors, imagery, vibe" list is cut because the phones
visual already shows it (no narrating the picture, rule 10). The 75+ designs / custom proof point
stays in the blurb (not split into a separate caption) — a real differentiator and a concrete number
the visual can't state, so it earns its place in the copy.

_How it's displayed:_ header + blurb with a row of phones showing the app across brand themes. Being a
static sheet, it packs in as many phones as fit (more than the landing's three) to show the variety.

---

## 5. Footer (book the demo)

**Status:** LOCKED

_What it says:_

- **Closing headline:** "Keep more members."
- **CTA:** "Book a 15-minute demo"
- **Contact:** jesse@combatden.net · 832-871-2702 · combatden.net

Value-first closing headline (the landing §8 footer line), above the action CTA per the value-CTA
pattern. The hero/footer bookend ("keeps members from quitting" / "Keep more members") is deliberate:
a leave-behind hammers one message top and bottom. The landing §7 ROI stats (5× cheaper / $9,000 a
year) are NOT carried onto the sheet — dropped to keep the close clean.

_How it's displayed:_ centered closing headline, the "Book a 15-minute demo" CTA beneath it, and the
contact line (email · phone · URL) at the foot. No form (print sheet), no ROI band.
