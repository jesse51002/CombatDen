// One worked example of a brand brief, for the "Load an example" action.
//
// WHY IT SHIPS: the long description is a 300-word authored document, not a
// field anyone types in front of a buyer, and its SHAPE is the thing a new
// author gets wrong — a brief that says "modern and premium" produces a theme
// that says nothing. This example is written in the register the real ones use
// (`ThemeService/apps/combatden/*/customization.yaml`): audience, voice, the
// hard NOT-this, then the five-part visual system every generated asset wears,
// ending in the hard nos.
//
// It is a NEW brand, deliberately not a copy of one of the 76 already in the
// catalog — loading it and pressing Launch generates a design nothing else in
// the library already is.

import type { BriefInput } from './studioApi';

export const EXAMPLE_BRIEF: BriefInput = Object.freeze({
  design_direction: Object.freeze({
    name: 'Northgate Boxing',
    short_desc:
      'A working boxing gym under a railway arch — plain, honest and hard, where the only thing that counts is the round you just finished.',
    long_desc: `Northgate Boxing is an amateur boxing club and its member app. It
sits under a railway arch in a working part of town and has done for
forty years: chalk on the floor, a bell on the wall, a bucket by the
ring. The members are shift workers, students and a handful of
competing amateurs — people who come after work, do the rounds, and
go home. Nobody is here to be photographed.

The voice is plain and dry, the way a coach who has watched ten
thousand rounds actually speaks: short sentences, no adjectives it
has not earned, credit given once and quietly. "Six rounds. Same
again Thursday." It never hypes ("BEAST MODE"), never flatters
("amazing job!"), never sells.

The anchor is the equipment itself — the bell, the bucket, the wrap,
the bag chain — rendered as the honest objects they are.

Visual system — the shared look every generated asset must wear:

- Feel: plain, worn, hard-wearing. Built for use, not for display.
  Weighty and grounded, with nothing decorative anywhere on it.
- Medium & materials: real gym stock — scuffed leather, canvas duck,
  cotton wrap, galvanised steel, painted brick, chalk dust. Matte and
  used, with the marks of use kept rather than cleaned off. Never
  plastic, never glossy, never pristine.
- Finish & light: one hard overhead work-light in a dim room. Strong
  directional light, honest shadow, deep falloff into the dark. No
  glow, no rim light, no studio softbox.
- Energy by role: a celebration lands like a bell — one solid strike,
  then quiet. Persistent icons are flat, small and utterly still.
  Earned, never loud.
- Hard nos: no flames, skulls, lightning or blood; no neon, chrome or
  holographic sheen; no confetti; nothing cute, cartoon or pastel; no
  motivational-poster gloss.`,
  }),
  colors_direction: Object.freeze({
    description: `A dark, plain palette taken from the room itself — colour does
the work of paint on brick, not of a brand guideline.

- Primary: a deep worn oxblood / dried-blood red, the colour of old
  gym leather. Saturated but heavy and low-lit, never a bright
  signal red and never orange.
- Background: a warm near-black with a brown-grey undertone, like an
  unlit arch. Held off pure black so the light has somewhere to fall.
- Text: a chalk off-white, slightly warm and slightly soft,
  comfortably above AA on the canvas, never a harsh pure white.
- Accent: a dull brass / bell-metal yellow for the small earned
  marks — a clearly different hue from the oxblood, used sparingly
  and never as a fill.`,
    mode: 'dark',
  }),
});

/** The run name the example suggests — a folder that does not exist yet. */
export const EXAMPLE_RUN_NAME = 'NorthgateBoxing';
