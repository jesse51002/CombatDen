// A REAL `GET /apps/combatden/ApexMMA` payload, trimmed to a few slots per
// section but otherwise byte-shaped like the wire.
//
// Traced from ../../../../../apps/combatden/ApexMMA/output.yaml as reshaped by
// ../../../../../src/api/schema/output_response.py: `images` / `fonts` /
// `icons` collapse to flat `slot -> string` maps, while `color_set`, `font_set`
// and `text_set` pass through from disk UNCHANGED and `image_set` is the same
// images restated with their complexity tier — which is why the noise the
// pipeline writes (`overwrite_specs`, the oklch/hsl/hex formats next to `rgb`)
// is reproduced here, and why every image URL appears twice. A parser that
// silently depends on that noise being absent would pass a hand-written
// fixture and fail in prod.
//
// The numbers are the genuine ones: `primary` is #d40c1a, its `second` carries
// alpha 0.75, its `card` alpha 0.126, and every opaque colour ships
// `alpha: null` rather than `alpha: 1`.

function colorValue(
  r: number,
  g: number,
  b: number,
  alpha: number | null,
  hex: string,
): Record<string, unknown> {
  return {
    oklch: { l: 0.55, c: 0.22, h: 27.0, alpha },
    hsl: { h: 355.72, s: 89.36, l: 43.88, alpha },
    rgb: { r, g, b, alpha },
    hex,
  };
}

const LOGO_URL =
  'https://cdn.combatden.net/combatden/ApexMMA/images/logo_primary.png?v=ea55f9b64030';
const CELEBRATION_URL =
  'https://cdn.combatden.net/combatden/ApexMMA/images/celebration_image.png?v=fbdccc4f9e48';

export const APEX_MMA_PAYLOAD: Record<string, unknown> = {
  app: 'combatden',
  display_name: 'CombatDen',
  design_name: 'Apex MMA',
  // The run's classification bucket — the value `GET /apps/{app}/styles`
  // filters on, now carried by the single-run response too.
  category: 'Fighting',
  images: {
    logo_primary: LOGO_URL,
    celebration_image: CELEBRATION_URL,
    // Present-but-empty is what a run mid-`expand` ships. It must read as absent.
    trophy_image: '',
  },
  // The same images, restated with the tier that picked the generator's
  // quality. The flat map above is this group's `url` field, flattened.
  image_set: {
    images: {
      logo_primary: { url: LOGO_URL, complexity: 'high' },
      celebration_image: { url: CELEBRATION_URL, complexity: 'high' },
      // No tier: the slot is on the wire, but nothing classified its prompt.
      trophy_image: { url: '', complexity: null },
    },
  },
  fonts: {
    body: 'Roboto Flex',
    display: 'Space Grotesk',
  },
  // The font group, verbatim off disk — the family the flat map above carries,
  // plus the three fields it cannot: Google's category for the family, the
  // run's own name for the face, and the run's written reasoning.
  font_set: {
    fonts: {
      body: {
        overwrite_specs: { specs: '', image_to_image: null },
        family: 'Roboto Flex',
        category: 'sans-serif',
        display_name: 'Professional Grotesque',
        description:
          'A clean, high-legibility sans-serif optimised for UI and reading text at 13–18px. Strong weight range (Regular through Bold) provides hierarchy without ornament, letting the display font take the lead.',
      },
      display: {
        overwrite_specs: { specs: '', image_to_image: null },
        family: 'Space Grotesk',
        category: 'sans-serif',
        display_name: 'Athletic Modern',
        description:
          'A confident geometric sans with sharp proportions and clean letterforms that read decisively at large sizes. Built for display and headlines, it carries the brand’s modern athletic energy.',
      },
    },
  },
  icons: {
    nav_home: '/apps/combatden/ApexMMA/icons/nav_home?v=91f813afa263',
    nav_videos: '/apps/combatden/ApexMMA/icons/nav_videos?v=acbfe549c2a4',
  },
  color_set: {
    mode: 'dark',
    colors: {
      primary: {
        overwrite_specs: { specs: '', image_to_image: null },
        color: colorValue(212, 12, 26, null, '#d40c1a'),
        display_name: 'Red Corner',
        description: 'A bold, saturated competition red — the red corner.',
        derivations: {
          second: colorValue(212, 12, 26, 0.75, '#d40c1abf'),
          third: colorValue(212, 12, 26, 0.5, '#d40c1a80'),
          card: colorValue(212, 12, 26, 0.126, '#d40c1a20'),
          popup: colorValue(36, 7, 7, null, '#240707'),
          dark: colorValue(5, 0, 0, null, '#050000'),
          light: colorValue(255, 166, 156, null, '#ffa69c'),
          regular_text: colorValue(220, 231, 234, null, '#dce7ea'),
        },
      },
      accent: {
        overwrite_specs: { specs: '', image_to_image: null },
        color: colorValue(0, 185, 207, null, '#00b9cf'),
        display_name: 'Cage Cyan',
        description: 'The cool rim light.',
        derivations: {},
      },
      // A slot whose colour block never resolved. It must be skipped, not fatal.
      broken: {
        color: { hex: '#ffffff' },
        display_name: 'Broken',
        description: '',
        derivations: {},
      },
    },
    palette: {
      card: colorValue(220, 231, 234, 0.113, '#dce7ea1d'),
      primary: colorValue(212, 12, 26, null, '#d40c1a'),
      background: colorValue(10, 6, 4, null, '#0a0604'),
      text: colorValue(220, 231, 234, null, '#dce7ea'),
      accent_second: colorValue(0, 185, 207, 0.75, '#00b9cfbf'),
    },
  },
  text_set: {
    texts: {
      class_booked_headline: {
        overwrite_specs: { specs: '', image_to_image: null },
        value: "You're in.",
      },
      reserve_cta: {
        overwrite_specs: { specs: '', image_to_image: null },
        value: 'Lock it in',
      },
      // An empty override must fall back like an absent one.
      wins_title: { overwrite_specs: { specs: '', image_to_image: null }, value: '' },
    },
  },
};

/** One page of `GET /apps/combatden/styles`, per style_list_response.py. */
export const STYLES_PAGE_PAYLOAD: Record<string, unknown> = {
  items: [
    {
      id: 'ApexMMA',
      display_name: 'Apex MMA',
      celebration_image: '/apps/combatden/ApexMMA/images/celebration_image',
      category: 'Fighting',
    },
    {
      id: 'ZenBJJ',
      display_name: 'Zen BJJ',
      celebration_image: 'https://cdn.combatden.net/combatden/ZenBJJ/images/celebration_image.png',
      category: 'Fighting',
    },
  ],
  total: 76,
  offset: 0,
  limit: 20,
};
