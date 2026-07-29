You are choosing how a real, shipped product is ARRANGED for one brand —
the way a senior product designer picks a layout system once, for the
whole app, and then holds to it.

The brand is described below by its NAME and its brief. Below that is a
list of format slots. Each slot is one switchable surface of the product,
and each carries its OWN closed list of values. Exactly one value per
slot is the answer.

This is ONE batched decision, not a series of independent ones. Every
slot you answer belongs to the same product and will be seen by the same
user in the same session. Picks that are each individually defensible but
disagree with one another are a **fail** — a spare, unhurried brand that
lands a dense, high-energy arrangement on one screen and a calm one on
the next reads as two products stapled together. Decide what this brand
IS first, then answer every slot from that one decision.

How to decide:

- **The brief is ground truth.** What the brand is for, who it is for,
  and how it wants to feel decides the arrangement. The design name is a
  strong hint; the slot id is a hint only.
- **Read every value's description before answering that slot.** Each one
  describes the arrangement visually — its shape, what dominates it, what
  is demoted, what a member notices first. Picture it, then judge it. The
  token itself is a label, not an argument: never pick on the name alone,
  and never assume a plain-sounding name means a plain arrangement.
- **Serve the content, not novelty.** An arrangement that shows this
  brand's most important thing first beats a more unusual one that
  buries it. If a brand's whole promise is "know what's next", pick the
  arrangement that puts what's next first.
- **Do not pick by position.** The order of the values in each list
  carries no meaning — the first value is not a default, a
  recommendation, or a safe answer, and neither is the last. Answering
  every slot with its first value is a non-decision and a fail. So is
  reaching for the most unusual value in every list to look decisive.
- **Restraint is a real answer.** When a brand's brief genuinely calls
  for the plainest, quietest option in a slot, pick it and say so. A
  brand does not have to be loud on every surface — but it does have to
  be the SAME brand on every surface.
- **THERE ARE NO WRONG CHOICES HERE.** Every value in every list is a
  real, built, reviewed arrangement of the same product. None is a trap,
  none is a downgrade, and none is being marked against a hidden correct
  answer. The descriptions tell you what each one LOOKS LIKE — what is
  large, what leads, what recedes, what the eye lands on first — and they
  stop there on purpose. They do not tell you which brand should have
  which, because that judgement is yours and it is the entire reason you
  are being asked.
  So read what each arrangement looks like, hold the brand in mind, and
  say which one you would put it in. Trust that read. You do not have to
  build a case, hedge toward the middle, or pick the option that would be
  easiest to defend to someone else — an answer you could argue for and
  an answer that is right for this brand are different things, and the
  second is what is wanted.
  Two brands with genuinely different briefs should end up with
  genuinely different apps. If a hard competitive gym and a restorative
  studio would get the same answer from you, look again at what actually
  distinguishes this brand and choose from that.
- **You must choose, once, per slot.** There is no "either", no "it
  depends", and no second choice. If two values feel close, pick the one
  the brief spends more of its words supporting and name the runner-up in
  your reason.

HARD CONSTRAINT. Each value you return must come from **that slot's own
list**, copied **exactly** — same spelling, same capitalization, same
spacing. Do not invent a value, translate one, reshape its casing, or use
a value that belongs to a different slot. A value outside the slot's list
is rejected and you will be asked again.

OUTPUT. For EVERY slot listed below, return:

- `value`: the chosen token, verbatim from that slot's list.
- `reason`: one sentence naming the evidence in the brief that decided it
  (and the runner-up, if it was close). No marketing copy.

--- The brand ---
Design name: $name
In short: $short
In depth: $long
Colour brief: $colors

--- Already decided (do not change; match these) ---
$fixed_context

--- The slots to answer (one value each, verbatim) ---
$slots
$note
