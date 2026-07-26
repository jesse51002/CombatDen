# AI Agent Page — Visual Motif Brief

Three motif options for the new AI agent subpage (`ai.html`), whose content and six-section
structure are already locked in `new-pages-draft.md`.

**What this decides:** the one recurring graphic device that gives the page an identity, the way
ploy.ai has its inflated jelly shapes, Notion has its faces, and Stripe has its gradient line art.

**What this does not decide:** colors, typography, layout system, or copy. Those are already settled
by `DESIGN.md` and stay exactly as they are. Every option below is drawn in `#2A67BD` and its family,
on the `#f3f5f8` ground, set in Geist and Geist Mono.

The three are presented in no order and with no recommendation. They are genuinely different bets,
not variations on one idea.

**Founder verdict (recorded after review):** Blue Pencil is the clear favorite. The Slip is liked
("modern"), kept as a contender. The Day Rail is rejected outright, replaced below by **Option D —
The Counterweight**, which was asked to match Day Rail's level of conceptual ambition (reframing an
obvious category cliché, the way Day Rail turned "24/7" into a ruler instead of a clock) without
reusing a time-axis device. Day Rail's write-up is kept below for the record, not deleted, but is out
of the running.

---

## Fixed for all three

- **Palette:** the one-accent rule holds. `accent #2A67BD`, `accent-dark #1F5099`, `accent-soft
  #E8F0FB`, ink ramp, hairlines. No second brand color, no gradient text.
- **Type:** Geist for everything readable, Geist Mono for every label the motif carries (uppercase,
  9 to 12px, tracked). The mono is already the page's "this is a built product" signal, and each
  option leans on it rather than introducing a new type role.
- **Elevation:** layered soft shadows and the existing white-gradient card recipe. Nothing in a motif
  gets a hard single shadow or a colored side stripe.
- **Format-neutral:** no gloves, belts, fists, or mats in any option. Where an option needs a class
  name, it uses a mixed roster (Vinyasa Flow, Fundamentals, Interval 45, Open Mat, Barre Express) so
  the page works for a yoga studio and a BJJ gym without changing an asset.
- **Buildable with what the project has:** inline SVG and CSS only. Keyframes go in a section-local
  `<style>{...}</style>` block, the pattern `sections/feed.jsx` already uses. Scroll-triggered motion
  observes the shared `IN_VIEW_MARGIN` from `ds.jsx`. No 3D engine, no Lottie, no asset pipeline, no
  new dependency.
- **Reduced motion is a known gap on this site.** Whichever option is picked, its motion needs a
  static resting composition that still reads, so honoring `prefers-reduced-motion` later is a
  one-line change and not a redesign.
- **The §4 stats are illustrative.** All three options need a small mono disclaimer near the proof
  cards, since each makes the numbers look like real usage data.

## The rut we are steering around

The predictable AI-agent page ships one of: a glowing orb, a constellation of connected nodes, a
radar sweep, a purple-indigo gradient mesh with sparkle icons, or a chat bubble as the hero image.
`PRODUCT.md` already names purple gradients and blob graphics as anti-references, which rules out a
straight reskin of ploy's device even if we wanted one.

The other trap is the literal reading of our own metaphor. "An employee that never sleeps" wants to
become a cartoon robot mascot or a little character at a desk. That is also where Notion's faces
already live, so it would read as borrowed rather than owned. None of the three options below use a
character, a face, or a creature.

---

## Option A — The Day Rail

### The device

A 24-hour tick ruler. A hairline rule carrying a strict tick pattern: a 1px tick every 15 minutes, a
taller tick on the hour, a labeled tick in Geist Mono every three hours. Events sit on the rail as
small filled accent lozenges with a thin leader line out to a mono label.

It is a **ruler, not a clock.** No hands, no clock face, no circular dial with numerals. That
distinction is the whole thing: a clock is the obvious "24/7" cliché, a measured ruler is a piece of
instrument design that nobody in this category is using.

One geometry, three postures: the rail runs horizontal (under a headline, across a card), vertical
(as a page spine), or bends into a closed ring (once, at the end).

**Two pieces of signature furniture:**

- **The night band.** Wherever the rail appears, the 10pm to 6am span carries a faint `bg-alt` wash.
  The hours the owner is asleep become a visible stripe that repeats down the whole page. It argues
  the product's core claim without a word of copy.
- **The now cursor.** A single 2px accent line with a small filled cap, creeping along the rail at
  roughly 1px per second. It is the only element on the page that never stops moving, which is
  exactly the message.

### Motion

The rail draws itself in with `stroke-dashoffset` on scroll-into-view, about 700ms. Event markers pop
in staggered 60ms apart. Then everything freezes except the now cursor, which keeps creeping,
slowly enough to be almost subliminal. Restraint is the point: the page is still, one thing moves.

### Why it fits the story

Every claim on this page is temporal: "never sleeps," "24/7," "overnight," "this week," "ready before
you open the CRM." The rail makes time the substrate rather than the subject, so each claim gets
pinned to a moment. It also reframes the pitch honestly. The agent's real differentiator is not
intelligence, it is coverage of hours the owner does not have, and the night band shows that directly.

### Across the six sections

1. **Hero.** A full-bleed horizontal 24h rail spanning the viewport below the headline, night band
   shaded, with six or seven event markers already placed (the same events §5 will name in full).
   The now cursor sits at the current hour. The CTA button sits on the rail's centerline so the rail
   passes behind it: the action is literally on the timeline. The rail is the hero image; there is no
   other illustration.
2. **Problem statement.** The same rail, empty. Ticks only, no markers, except one dense cluster
   jammed into 6 to 8pm, the two hours the owner is actually at the desk doing it themselves. The
   headline "Your gym software waits for you to do everything" sits above a day that is two hours
   long. No chart, no copy, the argument is made by absence.
3. **Monitor / Plan / Execute.** All three cards carry the same rail fragment at their top edge, in
   three states. **Monitor:** markers scattered evenly across all 24 hours. **Plan:** the markers
   converge with thin connectors into a single bracket with a mono label. **Execute:** the bracket is
   closed by one accent cap marker reading `APPROVED`, and the rail continues past it uninterrupted.
   Read the three headers and you get the story; read only the three rails and you get it too.
4. **Proof (4 stat cards).** Numeral on the left, and to its right a compressed seven-day rail in the
   same tick grammar (one tick per day, M T W T F S S in mono). **Chat:** nine markers bunched into
   business hours. **Member:** twelve markers, two ringed (the win-backs). **Competition:** four
   markers, one per detection. **Growth:** three markers plus a shaded span *past* the now cursor,
   the slow week it is planning into. Growth is the only card whose rail extends into the future,
   which is precisely what separates that card from the other three.
5. **The employee log.** The rail turns vertical and becomes the section's spine. The eight entries
   hang off it **at their true position for that time of day**, so 6:10am and 6:40am sit tight
   together and 11:50pm sits far below, with the night band shading the top and bottom of the column.
   The uneven spacing is the evidence. "One agent. All day. Every day." sits at the bottom cap.
6. **Final CTA.** The rail bends into a closed ring, its only closure on the page, with the demo CTA
   at the center. Night band still shaded, now cursor still creeping around it. One continuous loop
   as the closing argument.

### What makes it ownable

Nobody in gym software or AI SaaS is using measured instrument notation as a graphic system, and the
night band is a shape you would recognize cropped, with the logo removed.

### Honest risk

It is quiet. Hairlines and mono labels can slide into "tasteful chart furniture" instead of reading
as a motif. It only works if it is committed at scale: a genuinely full-bleed hero rail, a genuinely
tall log spine. And because "24/7 means clock" is one step from obvious, the ruler rendition and the
night band cannot be softened back toward a dial or the option loses its reason to exist.

### Build notes

Ticks are one component mapped over an hours array. Draw-in via `stroke-dasharray` /
`stroke-dashoffset` keyframes in a section-local `<style>` block. The now cursor is one long-duration
CSS `translate` keyframe or a single `requestAnimationFrame` loop. Zero images. On mobile every
horizontal instance collapses into the same vertical posture the log already uses, so there is one
responsive fallback to build rather than six.

---

## Option B — The Slip

### The device

One repeated object: a small white slip of drafted work. Radius 12 to 14, deliberately tighter than
the page's 22px cards so a slip reads as a different class of object. A hairline top border, a mono
header row (timestamp plus category), one line of ink body text, and a **perforated bottom edge**, a
row of tiny notches marking a tear line. Every piece of the agent's output on the page is a slip.

Slips behave like physical objects: they stack (4px offset, rotation under 1.5°), fan, thread onto a
spike, and drop into place.

**The approval mark** is the counterpart device and the load-bearing half of the motif. A blue mark
that lands on a slip: a rounded square with a check, or a compact stamp block with mono `APPROVED`
and a timestamp, set at a 2 to 3° rotation as if pressed by hand. Un-approved slips carry an **empty
approval well** in the same spot, a dashed hairline square waiting to be filled. That empty well,
repeating down the page, is the trust argument made as a shape.

**Iconography** is capped at four 12px hairline glyphs in the mono header, one per §4 category: a
person outline, a storefront, a speech caret, an upward tick. No robot, no brain, no sparkle, ever.

### Motion

Slips arrive. A slip fades in and settles 6px downward over 220ms, and the stack beneath it shifts
2px, once. The approval stamp lands with a 160ms scale-from-1.06 plus a single 1px shadow bloom, then
holds. Nothing loops except one slow three-step demo in the Execute card. Paper does not jitter, and
the restraint is what keeps it premium.

### Why it fits the story

The differentiating claim on this page is not autonomy, it is the **approval gate**: "Approve it
once, and it runs on its own from there." A motif built on output-waiting-for-a-signature argues that
in every section without restating the sentence.

It also solves the hardest problem in selling an agent: its work is invisible. The slip turns that
work into a countable object, and a stack of slips is a self-evident volume argument. This is how
much it did while you were gone.

### Across the six sections

1. **Hero.** A loose vertical fan of six slips rising beside the headline out of a soft shadow at the
   bottom, as if pushed up from below overnight. Each carries a real mono timestamp and one line of
   drafted work. The topmost slip carries the blue approval mark; every slip below it carries the
   empty well. The CTA is the only solid blue object in the composition, so the eye reads: a stack of
   drafts, then your one action.
2. **Problem statement.** A single slip, alone and centered, blank except for its mono header, with an
   empty body and an empty approval well. Nothing was drafted. One small object in a lot of air,
   under "Your gym software waits for you to do everything."
3. **Monitor / Plan / Execute.** The same object at three moments of its life. **Monitor:** a scatter
   of partial slips cropped by the card edge, timestamps only, no body text yet, raw observations
   piling up. **Plan:** one complete slip centered, body filled in, empty approval well, faint slips
   stacked behind. **Execute:** the identical slip with the mark landed, and below it a small mono
   ledger of what ran afterward (`SENT 8:02AM · SENT 8:02AM · SENT 8:03AM`). Three cards, one object,
   photographed three times.
4. **Proof (4 stat cards).** Each stat card **is** a slip at large scale. Mono header with its
   category glyph, the big Geist 700 numeral, the action line set as the slip's body, the secondary
   stats in a hairline row just above the perforation, and the live status line printed *below* the
   tear line in `ink-faint` mono, like the stub of a receipt. The card family is the motif; nothing
   decorative is added.
5. **The employee log.** The receipt spike. A vertical hairline rail with all eight slips threaded
   onto it in time order, each rotated a hair (alternating ±0.8°) and overlapping the one above by
   about 10px, so the column reads as a real day's spindle of work. Approved entries carry the mark,
   the last two still carry the empty well. "One agent. All day. Every day." sits below the final
   slip, like the tail of the roll.
6. **Final CTA.** One blank slip, larger than any other on the page, with the booking form sitting
   where the body text goes, and the approval well drawn around the primary button itself. The CTA
   *is* the mark you are being asked to make.

### What makes it ownable

The empty approval well is a shape you would recognize on a billboard, and no competitor is selling
the approval gate as their visual identity. They all sell autonomy, which is the thing gym owners are
actually nervous about.

### Honest risk

Paper drifts warm. Every real-world reference for this (receipts, tickets, memos, order tickets) is
kraft or cream, and rendering it that way would break the cool-neutral system on contact. It has to
be built from the existing white-gradient card recipe with cool shadows, letting the perforation and
the slight rotations carry all of the "paper." Second risk: stacking and rotation done carelessly
reads as scrapbook. Angles stay under 2°, shadows stay in the layered-soft recipe, or it looks cheap.

### Build notes

One `<Slip>` component with `time`, `category`, `body`, and `state` props carries the whole page. The
perforation is a repeating radial gradient on a 6px strip, pure CSS, no image. Stamps and glyphs are
inline SVG at 1.5px stroke. Stacking is absolute positioning plus `transform: rotate()`. On mobile the
hero fan collapses to a straight stack and the spike needs no change, since it is already vertical.

---

## Option C — Blue Pencil

### The device

The agent never draws itself. It draws **on your gym.** The motif is a markup layer: accent-blue
marks that land on top of real content (a class schedule, a member roster, a booking chart, a
competitor's post, an app screen). The name is literal: the blue pencil is the copy editor's mark-up
tool, and it happens to land exactly on this site's single accent.

The mark vocabulary is small and fixed, five shapes and no more:

- **the ring** — a hand-inflected ellipse (one SVG path with a 1 to 2% wobble, not a perfect circle)
  around the thing that matters
- **the bracket** — a square-cornered `[` `]` pair spanning a range
- **the leader** — a thin line from a mark out to a mono note, with a small filled dot at the anchor
- **the margin flag** — a small blue tab in the left gutter marking a row worth reading
- **the strike** — a single line through what the agent ruled out

Stroke 1.5 to 2px, round caps, accent blue. Notes in Geist Mono, uppercase, at the existing label
size. **Marks never sit on empty background.** They always attach to content, which forces every
section on the page to show something real.

No highlighter fills, no red, no sticky notes, and no named cursor avatars, which is the
Figma-multiplayer cliché and reads as collaboration software rather than an agent.

### Motion

Marks draw on. Each ring or bracket animates its path with `stroke-dashoffset` over about 380ms with
a slight overshoot, then its leader extends, then the mono note fades in. Marks arrive in sequence,
roughly 250ms apart, gated on scroll-into-view. They never erase: once a section's marks are drawn
they stay. One card (Execute) may loop a short three-mark sequence.

### Why it fits the story

This is the only option that shows the agent's **input** as well as its output. The pitch is that it
reviews the industry, checks in on members, and watches competitors, all of which are acts of
reading. A markup layer makes the reading visible, and more usefully it makes obvious that the agent
is reading *this gym's* data rather than producing generic AI output.

It also inherits directly from what the live homepage already does in §4, where check and X marks
land on real video thumbnails. The new page would read as the same company, one idea further along,
rather than a separate microsite.

### Across the six sections

1. **Hero.** Behind the headline sits one large real artifact: a week of the gym's class schedule,
   the grid every owner reads daily. As the hero settles, five marks land in sequence: a ring around
   a half-empty Tuesday 6pm, a bracket over a run of three missed check-ins with a mono note, a
   margin flag on one member row, a strike through a class it ruled out, and a leader pointing at
   next Thursday reading `SLOW WEEK`. The visitor understands the product before reading a word.
2. **Problem statement.** The identical artifact, completely unmarked. Clean, inert, a little too
   quiet, under "Your gym software waits for you to do everything." The absence of marks is the whole
   illustration, and it lands hard because the hero just showed what marked looks like.
3. **Monitor / Plan / Execute.** Each card holds a different marked artifact. **Monitor:** a dense
   member roster with three margin flags, one ring, and a mono count in the corner. **Plan:** a
   bracket around the flagged rows with a leader out to a drafted message written in the margin.
   **Execute:** that draft with a single blue check drawn beside it and the mono line
   `APPROVED BY YOU`, and the roster marks resolving to a filled state. The difference between the
   three steps is carried by *which marks appear*, which is a much stronger device than three icons.
4. **Proof (4 stat cards).** Each card shows a cropped real artifact behind a light scrim, the
   numeral over it, and exactly one mark matching that card's action line. **Chat:** a question in a
   chat pane, ringed, leader to `12S`. **Member:** three roster rows flagged, two of them ringed (the
   two who came back). **Competition:** a competitor's post with a bracket around its date and the
   note `FALL PROGRAM`. **Growth:** a booking chart with a bracket over the August dip and a leader
   reading `DRAFTED: BRING A FRIEND`. Four different artifacts, one mark grammar holding them
   together.
5. **The employee log.** The log becomes a marked-up page. The eight entries sit as plain ink text
   rows, and every mark lives in the left gutter: a margin flag per entry (solid for done, hollow for
   pending), the mono timestamp outside the flag, and a hairline bracket joining entries where one
   action followed another (6:10 found, 6:40 messaged). The overnight run carries a single tall
   gutter bracket labeled `WHILE YOU WERE CLOSED`.
6. **Final CTA.** The CTA card is itself the artifact, and the last mark on the page is a ring drawn
   around the demo button as the section scrolls in. It is the only mark on the page aimed at the
   reader instead of at the gym.

### What makes it ownable

A fixed alphabet of five marks applied to real content is exactly how identity systems become
recognizable. Cropped to one ring and one mono note, it would still read as CombatDen. It is also the
only one of the three that carries a little humor and personality, which is the quality the founder
liked in Notion's faces, without borrowing anything from them.

### Honest risk

It is by far the most content-hungry option. Every section needs a believable artifact underneath
(schedule, roster, chart, competitor post, chat pane), which means authoring five or six
synthetic-but-convincing screens before a single mark can land. If those artifacts are weak, the
marks have nothing to sit on and the motif collapses. It also needs the clearest "illustrative, not
real data" disclaimer of the three, because the artifacts will look like a real gym's numbers.
Finally, the hand wobble on the ring is a taste dial: too much and it fights the "product-grade
calm" north star, none at all and it loses the personality that makes it this option.

### Build notes

Marks are SVG overlays absolutely positioned over the artifact containers, using percentage
coordinates inside a `viewBox` so they scale with the artifact. Draw-on via `stroke-dashoffset`
keyframes in a section-local `<style>` block. Artifacts are plain JSX and CSS mock UI, the same
technique already used in `mocks/` and `sections/feed.jsx`. On mobile, artifacts crop to their marked
region rather than scaling down, since a full schedule grid at 375px is unreadable, so each artifact
needs a designated crop box defined up front.

---

## Option D — The Counterweight

### The device

A simple beam balance. One pivot, one thin hairline beam, two ends: **YOU** on the left in Geist
Mono, **AGENT** on the right. Small filled accent circles ("weights") drop onto the AGENT side, one
per completed task, and the beam tilts to carry them. The YOU side stays close to bare throughout.
This is not a device about *when* work happens (that was Day Rail's territory), it is a device about
*who is carrying it*.

**Two pieces of signature furniture:**

- **The cap.** The beam has a maximum tilt, roughly 14°, that it can never cross no matter how many
  weights land. It tips, it never inverts. The message is "lighter load," not "replaced," and the cap
  is what keeps the device honest about that.
- **The settle.** Every weight drop is a small physics moment: the token falls, lands with a soft
  bounce, and the beam eases into its new angle over about 300ms, then holds completely still.
  Restraint carries over from the other options: one thing moves, everything else is fixed.

### Motion

A weight drops in with a two-stage animation (fall, then a small settle-bounce on landing), the beam
re-balances with a spring-eased rotate. Once a section's weights have landed, the composition holds,
matching the "still, one thing moves" rule the other options already establish.

### Why it fits the story

The headline is "Your gym software waits for you to do everything," a workload sentence, not a time
sentence. "Approve it once, and it runs on its own from there" is a trust argument, and a balance,
literally a device for *equilibrium*, argues trust visually before the copy does. And every §4 number
("$3,600 in retention saved," "12 members flagged") is already a countable unit of work, which a
weight token represents directly: one thing off your plate, one token.

### Across the six sections

1. **Hero.** A wide beam beneath the headline, already carrying 3 or 4 settled weights on the AGENT
   side, the YOU side essentially bare. The imbalance the headline names is drawn before a word of
   body copy is read.
2. **Problem statement.** The identical beam, perfectly level, both sides empty. Nothing has been
   lifted yet, under "Your gym software waits for you to do everything." The absence is the
   illustration, the same device used empty a second time, the pattern Day Rail and The Slip both also
   leaned on for this section.
3. **Monitor / Plan / Execute.** Three small beams. **Monitor:** weights steadily piling onto the
   AGENT side. **Plan:** one weight paused mid-air, not yet dropped. **Execute:** the weight lands, the
   beam settles, and a small mono readout underneath reads `-1 FROM YOUR SIDE`.
4. **Proof (4 stat cards).** Each numeral sits beside a small companion beam instead of a trend line,
   showing that category's relative load shift: Member carries several weights, Competition fewer,
   matching the beam count loosely to the card's own stat.
5. **The employee log.** The beam turns vertical, pivot at the top, running as the log's spine. A
   weight drops at each timestamped entry's position, so by 11:50pm the AGENT side is stacked with a
   full day's drops, a day's work made countable the same way Day Rail made uneven spacing countable
   and The Slip made the receipt spike countable.
6. **Final CTA.** One last weight hovers, undropped, directly above the demo CTA button. The one thing
   only the owner can do is press it, and pressing the button is the drop.

### What makes it ownable

No AI-agent competitor uses a mechanical balance as its visual identity. The association is justice,
classic scientific instruments, or e-commerce price comparison, none of which is SaaS-dashboard
territory, so it reads as considered rather than borrowed from the category.

### Honest risk

Rendered too literally (illustrated scale pans, a cartoon bowl), it slides straight into
weight-loss-app or productivity-app cliché. It has to stay abstract: thin lines, small tokens, no
illustrated bowls. The tilt cap also has to hold exactly, a beam that tips too far reads as "the agent
takes over," which contradicts the approval-gate story this page is actually telling.

### Build notes

One SVG or CSS construction per beam: a line, a small triangular fulcrum, circles for weights,
`transform: rotate()` on the beam driven by weight count (roughly 2° per weight, capped near 14°).
Weight-drop is a two-keyframe CSS animation (fall, then bounce-settle). Zero images, same buildability
profile as the other options.

---

## Side by side

Dimensions, not scores. All three clear the bar; they trade differently.

| | **The Day Rail** | **The Slip** | **Blue Pencil** |
|---|---|---|---|
| Core idea | time coverage | work product awaiting your signature | reading and marking your actual gym |
| Argues best | "never sleeps" | "nothing runs without you" | "it watches *your* gym, not gyms in general" |
| Register | quiet, technical, measured | tangible, restrained, physical | active, a little quirky |
| Where the personality lives | the night band | the empty approval well | the hand-drawn ring |
| Content it needs | timestamps only (already written) | slip copy only (already written) | 5 to 6 authored artifact screens |
| Motion character | one slow continuous cursor | discrete arrivals plus a stamp | sequenced draw-on |
| Heaviest lift | making hairlines register at full scale | keeping the paper cool, never warm | authoring convincing artifacts |
| Reuse on the homepage later | high, sits under any section | medium, needs output to show | high, §4 already half does it |
| Closest failure mode | reads as chart furniture | reads as scrapbook | reads as a screenshot with stickers |

## Once one is picked

1. Whether the motif also gets retrofitted onto the homepage, or stays exclusive to `ai.html` as a
   deliberate difference between the two pages.
2. The disclaimer wording and placement for the illustrative §4 stats, which every option needs.
3. The reduced-motion resting state for the chosen motion (each option's static composition needs to
   stand on its own).
4. For Blue Pencil only: the artifact list and the gym-format mix inside each artifact, decided
   before any design work starts, since the marks depend on them.
