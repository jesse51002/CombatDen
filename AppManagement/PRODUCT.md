# Product

## Register

product

## Users

Owners and staff of **class-based gyms** managing their gym from a desktop browser. The
vertical is broad on purpose: yoga, pilates, CrossFit, dance, indoor cycling, barre,
climbing, martial arts, kickboxing, boxing, and franchised concepts (F45/OrangeTheory).
Combat sports is the *starting sales wedge* where the founder has cultural fluency, not
the ceiling, so the admin tool must read as credible to a pilates studio owner and a BJJ
gym owner alike.

These users are not analysts and not full-time software operators. They run a floor, coach
classes, and dip into the admin tool between sessions to do a specific job: check who is
showing up, manage member ranks/progression, configure the points-and-rewards loop, and
curate the contextual content their members see. Their context is short, interrupted
sessions, often on a laptop in a noisy gym, not long focused stints at a desk.

The job to be done: **see the health of the retention engine and adjust it, fast.** Not run
payroll, not handle billing, not operate check-in. AppManagement deliberately sits *beside*
the gym's existing CRM and never touches the operational critical path.

## Product Purpose

AppManagement is the **gym admin web app** for a member-retention layer that runs alongside
a class-based gym's existing CRM. The member-facing mobile app delivers contextual training
content, points-based rewards, and attendance-based rank progression; AppManagement is where
the owner configures and monitors all of that.

The company's bet is **retention engagement + design**, not feature parity. Incumbents
(Mindbody, PushPress, Zen Planner, Wodify, Glofox, Trainerize, Mighty Pro) handle billing
and scheduling and stop there; none ship a real between-class engagement layer, and all cap
brand customization at logo + palette. AppManagement wins by making the retention engine
legible and by *looking* like a product worth premium money.

Success for this surface: an owner can answer "is my retention engine working, and what do I
change?" in under a minute, and a prospect watching a sales demo of these screens believes
the product is more crafted than anything else they're shopping.

**Note on scope:** this is currently a visual-only prototype (no backend, no state framework,
hardcoded mock data) built for demos and design iteration during pre-build sales / MVP. It
also doubles as a live sales artifact — screens get screenshotted to sell. Design rigor is
not relaxed because it's a prototype.

**Note on visual direction:** AppManagement has a fresh, standalone visual identity, forked
from the sibling member app and FlutterCRM (which share an immutable token file). The fork is
deliberate: the admin tool is staff-facing and lives in a different context than what members
see, so it does not have to wear the members' skin. The "byte-for-byte identical
design_constants" rule in CLAUDE.md no longer binds this repo. The shipped direction is a warm
light theme (paper + ink) with a single sapphire accent, Hanken Grotesk, tight corners, and a
de-carded layout (sections separated by hairlines, cards reserved for discrete objects). Full
spec in DESIGN.md.

## Brand Personality

**Confident, premium, quietly authoritative.** Three words: *crafted, calm, credible.*

The owner should feel they are using an expensive, well-built product — one whose polish
signals the company's design competence without ever shouting it. The tool projects authority
through restraint, not through gym-bro intensity or gamified flash. It is the opposite of a
spreadsheet and the opposite of a neon dashboard.

Vertical-neutral in voice and imagery. No combat-sports coding (no fists, cages, or
aggressive type) that would read wrong to a yoga or barre studio owner. The identity is a
strong, brandable, premium SaaS personality that any class-based gym owner would be proud to
have running on their laptop.

## Anti-references

- **Incumbent gym CRMs** (Mindbody, PushPress, Zen Planner, Wodify back-offices) — dense,
  dated, operational-CRM clutter. We are not another gym back-office; we must not look like
  one.
- **Spreadsheet density** — walls of tiny data at uniform weight, no hierarchy, every cell
  fighting for attention. The retention engine must be *read*, not deciphered.
- **Generic SaaS admin** — Bootstrap-y gray cards, blue hyperlinks, default-everything
  dashboards, the hero-metric-with-gradient cliché. If a viewer could say "AI/template made
  that," it has failed.
- **Combat-sports machismo** — fight imagery, cage motifs, aggressive condensed display type.
  Off-brand for the generalized class-based-gym positioning.

## Design Principles

1. **Design is the product, even back-of-house.** The whole company bet is design-as-product.
   The admin tool is a live sales artifact, so it must look as crafted as the member app even
   on screens no one would screenshot. Polish is load-bearing, not decoration.
2. **Make the retention engine legible.** Attendance, ranks/divisions, points, rewards, and
   content curation are the subject. Surface their *state and health* first; bury operational
   minutiae. The owner's one-minute question — "is it working, what do I change?" — drives
   every screen's hierarchy.
3. **Confidence through restraint.** Premium reads as quiet authority: clear hierarchy,
   breathing room, deliberate emphasis. Beat the spreadsheet-dense incumbents by showing
   *less, clearly* — not by adding chrome.
4. **Vertical-neutral, brandable canvas.** The admin identity must hold up across yoga to MMA.
   No imagery or type that codes to one sub-vertical. Combat sports is the wedge, not the
   brand.
5. **Convention where it's load-bearing.** Owners pattern-match to admin tools they already
   know. Don't reinvent normalized flows (tables, filters, detail views, settings); spend the
   creativity budget on identity and on making the retention data sing.
6. **Built for the mechanical swap to real data.** Even as a prototype, mock model field names
   and types mirror what the real API will return, so graduating to live data is mechanical,
   not a redesign.

## Accessibility & Inclusion

- **WCAG AA contrast** for text and meaningful UI against the chosen theme — held as a hard
  floor while picking any new palette.
- **Reduced-motion support** — respect `prefers-reduced-motion`; any motion in the new
  direction must degrade gracefully to no/low motion.
- No other formal requirements captured yet (prototype phase); revisit WCAG level and
  keyboard-operability targets when the app graduates to real data.
