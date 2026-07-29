// The web half of ../../ThemeFlutter/lib/theme/theme_font.dart.
//
// Dart hands the resolved family to `GoogleFonts.getFont(family)`, which fetches
// and registers the font itself. A browser needs the `@font-face` rules present
// before a `font-family` name resolves to anything, so this injects the Google
// Fonts CSS2 stylesheet for the family.
//
// WHY NOT ThemeService's `/apps/{app}/{run}/fonts/{slot}` endpoint: the wire's
// `fonts` map already carries the family NAME (see ../src/api/schema/
// output_response.py — `fonts={slot: font.family}`), and the CSS2 URL is a pure
// function of that name. Calling the endpoint would add a round trip per slot,
// on the startup path, to learn something already in hand — and its `variants`
// are TTF links, which is the wrong format for a browser (the CSS2 endpoint is
// what serves woff2).

/** Families already requested this session — a stylesheet per family, once. */
const injected = new Set<string>();

/** The weights the runtime asks for. Covers regular through bold headings. */
const WEIGHTS = '400;500;600;700';

/** The CSS2 stylesheet URL for a family. Pure; exported for tests. */
export function googleFontsCssUrl(family: string): string {
  const name = family.trim().replace(/\s+/g, '+');
  return `https://fonts.googleapis.com/css2?family=${name}:wght@${WEIGHTS}&display=swap`;
}

/**
 * Ensures a Google Fonts family is loadable, by injecting its stylesheet `<link>`
 * once. Idempotent per family, and a no-op outside the browser or for an empty
 * family. Never throws: a family Google does not have simply 404s the
 * stylesheet, and the `font-family` declaration falls through to the system
 * stack — the same degradation Dart gets from `GoogleFonts.getFont` throwing.
 */
export function loadFontFamily(family: string): void {
  if (family === '' || injected.has(family)) return;
  if (typeof document === 'undefined') return;
  injected.add(family);
  try {
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = googleFontsCssUrl(family);
    document.head.appendChild(link);
  } catch {
    // Nothing to recover; the system stack renders.
  }
}

/**
 * The `font-family` value to actually write into a style. Always ends in the
 * system stack so a family that failed to load still renders readable text.
 */
export function fontStack(family: string): string {
  return family === '' ? 'system-ui, sans-serif' : `"${family}", system-ui, sans-serif`;
}
