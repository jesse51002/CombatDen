# New Page — AI Agent Layer: Section Structure (draft, for approval)

Mirrors ploy.ai's real section structure closely (cards, numbered layouts, the timestamped-log
device, all of it), minus their three-engine platform breakdown (Web/Grow/Ads) and its
sub-feature lists, which don't map to a single-agent product. Everything else gets reskinned to
CombatDen's own design system and reframed for gyms, not rebuilt from scratch. Structure only
below except Hero. Approve the structure, then we fill in copy one section at a time; the actual
visual design (cards/animation treatment) is a separate design pass once content is locked.

**Proposed slug:** `ai.html`

1. **Hero** — done.
   - **Headline:** "Your gym software should be working harder than you are."
   - **Subline:** "Supercharge your gym with a 24/7 AI employee."
   - **CTA:** "Book a 15-minute demo"
2. **Problem statement** — done.
   - **Headline:** "Software shouldn't wait for you to do everything."
   - **Subtext:** CombatDen AI takes what you have and puts it on autopilot.
3. **How it works** — done. Three cards, Monitor → Plan → Execute. Carries the "nothing runs without you" trust point in the Execute card instead of a separate section for it.
   - **Monitor** — "Watches members, compares gyms, and tracks industry."
   - **Plan** — "Message at-risk members, marketing pushes, seasonal discounts."
   - **Execute** — "Approve it once, and it runs on its own from there."
4. **Proof** — the specifics, four stat cards (ploy's device: big stat + trend, a "detected X → did Y" line, secondary stats, live status). Not a log, that's §5. All numbers below are illustrative placeholders, not real usage data.
   - **Header:** "Four things it never stops working on."
   - **Chat** — command interface, not a monitoring stream, framed as "requests handled" instead of a background stat.
     - Stat: **9** — "requests handled this week"
     - Action line: "Asked for last month's revenue by plan → answered in 12 seconds"
     - Secondary stats: Avg response 8s · Actions taken 6 · Reports pulled 3
     - Status: "Waiting on your next question"
   - **Member**
     - Stat: **$400** — "in retention saved this month"
     - Action line: "Found 5 at-risk members → messaged each, 3 came back"
     - Secondary stats: Members flagged 12 · Check-ins sent 8 · Win-backs 3
     - Status: "Reviewing this week's attendance"
   - **Competition**
     - Stat: **4** — "competitor signals caught this week"
     - Action line: "Nearby gym posted a fall program launch on Instagram → flagged as a seasonal trend"
     - Secondary stats: Promos tracked 2 · Posts reviewed 18 · Events flagged 1
     - Status: "Reading this week's posts"
   - **Growth**
     - Stat: **3** — "campaign ideas drafted"
     - Action line: "Slow week detected in August → drafted a \"bring a friend\" promo"
     - Secondary stats: Ideas drafted 3 · Trends found 5 · Seasons planned 2
     - Status: "Drafting next month's promo"
5. **The employee** — done (draft). A day-in-the-life timestamped timeline, mock/illustrative like §4, pulling across the four §4 categories plus four more (revenue, reputation, schedule, industry, drawn from `docs/Business/Autonomous_Agent_Capability_Inventory.md`) so it reads as one agent doing genuinely varied work all day, not clustered on one theme. Presentation shows two entries readable at once (the newest in focus, the previous one still legible just behind it), not strictly one at a time, so the deck doesn't demand a read-and-forget pace. **Deliberately does not reuse §4's own example for a shared category** (e.g. Member's log entry is not the same at-risk-members story as the §4 Member card) — a repeated example reads as filler and a visitor skips it.
   - **Header:** "An employee that never sleeps."
   - **Log:**
     - 6:10 AM — Found 2 members training without an active plan on file.
     - 7:15 AM — Matched a new five-star review to a member, recommended a thank-you discount.
     - 9:00 AM — Answered "who's overdue on payment" in 9 seconds.
     - 11:30 AM — Caught a competitor's fall sale, recommended you run one too.
     - 2:45 PM — Flagged Tuesday's 6pm class, underfilled three weeks running.
     - 4:15 PM — Found 4 members overdue on their promotions.
     - 6:00 PM — Spotted a seasonal opening for a New Year kickoff challenge.
     - 9:20 PM — Benchmarked your pricing against gyms your size nearby.
     - 11:50 PM — Compiled today's flags into tomorrow's summary, ready before you open the CRM.
6. **Final CTA** — book a demo.
   - **Headline:** "Supercharge your gym."

---

## Open questions

1. Structure look right now, or still cut/merge/add anything (e.g. the PloyBooks-style "pre-built strategies" section, or social-proof logos — both skipped here since we have neither logos nor a decided pre-built-plans product yet)?
2. Page slug — `ai.html` okay?
3. Once this is locked, the card/animation visual design (the actual look of §3–5) goes through a dedicated design pass per the repo's rule for UI work, using `DESIGN.md`'s system, not freehanded here. Good to proceed that way once content's settled?
