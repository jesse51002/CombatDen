// Ports ../../ThemeFlutter/lib/theme/engine_tokens.dart.

import type { Rgba } from './color';
import { rgba } from './color';

/**
 * The few non-brand constants the runtime's OWN resolvers need as last-resort
 * defaults, so the library depends on neither consuming app's design constants.
 *
 * These are only fallbacks: every call site that has a real value (icon
 * size/colour, a loaded brand colour) passes or resolves it, and these never
 * fire then. Brand colours still resolve LIVE — the values here are what render
 * when nothing is loaded at all, which is the white-label resilience property.
 */
export const EngineTokens = Object.freeze({
  /** Default icon edge length, in px. */
  iconSizeMd: 24,

  /**
   * Last-resort icon tint when no colour prop and no loaded `text` token apply.
   * `#F4F3EE`, the CombatDen default.
   */
  fallbackIconColor: rgba(244, 243, 238) as Rgba,

  /**
   * The system stack every resolved font falls back through. Ported from
   * ThemeFlutter's implicit behaviour: `GoogleFonts.getFont` degrading to a
   * bare `TextStyle()` when a family will not resolve.
   */
  fallbackFontStack: 'system-ui, sans-serif',
});
