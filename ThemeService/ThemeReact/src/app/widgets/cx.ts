// No Dart counterpart — Flutter composes widgets, CSS composes class names.
//
// The one-line `classnames` this package will not add a dependency for (see
// ../../../CLAUDE.md: "Keep the dependency count near zero").

export type ClassValue = string | false | null | undefined;

/** Joins the truthy class names. */
export function cx(...values: ClassValue[]): string {
  return values.filter(Boolean).join(' ');
}
