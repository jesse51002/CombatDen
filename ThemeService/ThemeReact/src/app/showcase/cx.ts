// No Dart counterpart — Flutter composes widgets, CSS composes class names.
//
// A LOCAL COPY of ../widgets/cx.ts, byte-identical. The showcase island may not
// import from ../widgets (eslint.config.js Gate 2a), and eleven lines is
// cheaper than either relaxing the gate or adding `classnames` (see
// ../../../CLAUDE.md: "Keep the dependency count near zero").

export type ClassValue = string | false | null | undefined;

/** Joins the truthy class names. */
export function cx(...values: ClassValue[]): string {
  return values.filter(Boolean).join(' ');
}
