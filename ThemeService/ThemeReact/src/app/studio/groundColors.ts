// The two grounds a brief can choose between, as real colours.
//
// They are here rather than in a stylesheet because BOTH surfaces need the
// same two values and one of them needs them as data: the brief form paints
// each `light` / `dark` option in the ground it stands for, and every plate on
// the run sheet paints itself in the chosen one until the finished theme
// supplies its real background. One definition, two readers.
//
// These are stand-ins, not predictions. The engine derives the actual
// background from the colour brief; these are only "a light room" and "a dark
// room", chosen off the ends of the catalog's own range so a transparent PNG
// authored for either is legible on its plate while the run is still going.

import { rgba } from 'theme-react';
import type { Rgba } from 'theme-react';

import type { ColorModeInput } from './studioApi';

/** A warm near-white — not a clinical pure white, which no brief asks for. */
export const LIGHT_GROUND: Rgba = rgba(251, 250, 247);

/** A cool near-black, held off pure black so light has somewhere to fall. */
export const DARK_GROUND: Rgba = rgba(23, 24, 27);

/** The stand-in ground for a mode, or `null` when the mode is not known. */
export function groundForMode(mode: ColorModeInput | null): Rgba | null {
  if (mode === null) return null;
  return mode === 'light' ? LIGHT_GROUND : DARK_GROUND;
}
