// Ports ../../../../../../MobileApp/lib/features/class_booking/data/
// mock_class_detail.dart — the class-detail payload every `class_format`
// arrangement is handed, and the demo values for the four fields a gym file
// does not carry.
//
// THE SPLIT IS THE DART'S OWN. `classData` is the class CARD — the content
// VideoService serves (name, photo, description, instructor name / bio /
// headshot) — and the four fields beside it are the ones no gym file has:
// location, date, address, and the static map. `MockClassDetail`'s own doc
// says exactly that, and keeping the two levels apart is what makes it obvious
// which half a tenant's real data would replace.
//
// `ClassLayoutData` (class_layout_data.dart) does NOT port, and its absence is
// deliberate rather than an omission. It exists to carry three dev CAPTURE
// HARNESS hooks — a body `ScrollController` and two `GlobalKey`s that
// `tools/capture/` scrolls and centres a tap pulse on — plus the `onReserve`
// navigation callback. This browser has no capture harness and no router, so
// all four would be null forever; the layouts take the `ClassDetail` directly.
// Same rule as the rest of this island: nothing gated on a host this public
// browser does not have gets ported (../../CLAUDE.md).
//
// THE TIME SLOT AND THE ATTENDING COUNT ARE BORROWED FROM THE SCHEDULE, not
// invented here. A gym file carries no schedule, so ../home/
// homeScheduleGenerator.ts synthesises both deterministically; reading day 0
// back out of it is what makes the detail screen agree with the Home screen
// about the very class it is showing. Inventing a second time here would let
// the two surfaces disagree in the same slideshow.

import { dayAt } from '../home/homeScheduleGenerator';
import { bundledClasses } from '../showcaseGroupDefaults';
import type { ShowcaseClassInfo } from '../showcaseContent';

import classLocationMap from './assets/class_location_map.png';

/**
 * The class card, resolved. Mirrors the subset of `MockClass` this screen
 * renders — the schedule's own demo-only fields (`isBooked`) are not on it,
 * because no arrangement of the detail screen shows them.
 */
export interface ClassCard {
  readonly name: string;
  readonly timeRange: string;
  readonly durationMinutes: number;
  /** Instructor display name. */
  readonly mentor: string;
  readonly imageUrl: string;
  readonly description: string;
  readonly instructorBio: string;
  readonly instructorImageUrl: string;
  /** Undefined drops the attending row, exactly as Dart's `int?` does. */
  readonly attending: number | undefined;
}

/** Ports `MockClassDetail`. */
export interface ClassDetail {
  readonly classData: ClassCard;
  /** e.g. "Your Gym ‧ Dallas, TX". */
  readonly location: string;
  /** e.g. "This week". */
  readonly dateLabel: string;
  /** Street address rendered under the map. */
  readonly address: string;
  /** Built URL for the static map image. */
  readonly mapSrc: string;
}

/**
 * `_kAddress`. Verbatim from the Dart, which is the member app's own demo
 * address and the one the bundled map tile actually depicts.
 */
const ADDRESS = '1336 Inwood Rd, Dallas, TX 75247';

/** `MockClassDetail.dateLabel`'s demo value. */
const DATE_LABEL = 'This week';

/** The city half of the location line; the gym half comes from the host. */
const CITY = 'Dallas, TX';

/**
 * Last-resort prose, used only when neither tier carries the detail text.
 *
 * THE LADDER FOR THESE THREE FIELDS IS PER-FIELD, NOT PER-TIER, and that is a
 * deliberate correction rather than an embellishment. `useShowcaseContent`
 * picks ONE tier for the whole class list — fetched wins, bundled is the
 * fallback — which is right for the three fields both tiers carry. It is wrong
 * for these three: `GET /theme/showcase-defaults` DECLARES them (they are
 * `str | None` on `FastApiBackend/src/theme/schema/theme_schema.py`) but its
 * source yaml leaves every one null, by its own header's admission — it was
 * ported from the CRM's bundled constants, which predate these fields. So with
 * the backend UP, a per-tier ladder hands this screen a class with no
 * description, no bio and no headshot, and the richer bundled copy sitting
 * right beside it is never consulted.
 *
 * `previewClassCard` therefore fills each missing field from the bundled class
 * of the same name before reaching for the constants below. The proper fix is
 * for that yaml to carry the fields (it is generated from the same
 * `VideoService/gyms/*.yaml` these were extracted from); until it does, this
 * keeps the screen showing real prose instead of three generic lines.
 */
const FALLBACK_DESCRIPTION =
  'Train alongside your team. Arrive ten minutes early for the warm-up; ' +
  'gear is available at the desk if you need it.';
const FALLBACK_INSTRUCTOR_BIO =
  'Coach at the gym, working with members of every level from their first ' +
  'session through to competition.';

/**
 * `fallbackClass` — the defensive sample for when the screen is opened with no
 * class at all. In the member app the schedule always passes one; here it
 * covers an empty demo-content list.
 */
const FALLBACK_CARD: ClassCard = Object.freeze({
  name: 'Class',
  timeRange: '6:00pm - 6:55pm',
  durationMinutes: 55,
  mentor: 'Coach',
  imageUrl: '',
  description: FALLBACK_DESCRIPTION,
  instructorBio: FALLBACK_INSTRUCTOR_BIO,
  instructorImageUrl: '',
  attending: undefined,
});

/**
 * Ports `detailFor` — wraps a class card with the non-API location/map detail.
 *
 * `gymName` is the HOST's gym identity, not a customization slot, so the
 * location line is built from it rather than from the Dart's hardcoded
 * "Global MMA". That is the one value in this file that is not verbatim, and
 * it is the same rule the topbar already follows: a theme pick must never
 * rename the mock's gym, and the gym name must never be the theme's.
 */
export function detailFor(classData: ClassCard, gymName: string): ClassDetail {
  return {
    classData,
    location: `${gymName} ‧ ${CITY}`,
    dateLabel: DATE_LABEL,
    address: ADDRESS,
    mapSrc: classLocationMap,
  };
}

/**
 * The class this screen previews: the FIRST of the resolved demo classes, which
 * is the one a member would have tapped at the top of today's schedule.
 *
 * Joins three sources. The card's own text comes off `ShowcaseClassInfo`; the
 * time slot and attending count off day 0 of the schedule generator, which
 * builds its rows from the same list in the same order (`baseClasses` maps 1:1
 * by index), so index 0 is the same class in both. The detail-only text falls
 * through to the BUNDLED class of the same name when the resolved tier omits
 * it — see `FALLBACK_DESCRIPTION` above for why that per-field step exists.
 */
export function previewClassCard(
  classes: readonly ShowcaseClassInfo[] | null | undefined,
  category: string | null = null,
): ClassCard {
  const info = classes?.[0];
  if (info === undefined) return FALLBACK_CARD;

  const scheduled = dayAt(0, classes).classes[0];
  // Matched by NAME rather than by index: both tiers carry the same four
  // classes per category, but only the name is guaranteed to line them up if
  // the fetched list is ever reordered.
  const bundled = bundledClasses(category).find((item) => item.name === info.name);

  return {
    name: info.name,
    timeRange: scheduled?.timeRange ?? FALLBACK_CARD.timeRange,
    durationMinutes: scheduled?.durationMinutes ?? FALLBACK_CARD.durationMinutes,
    mentor: info.instructorName,
    imageUrl: info.imageUrl,
    description: info.description ?? bundled?.description ?? FALLBACK_DESCRIPTION,
    instructorBio: info.instructorBio ?? bundled?.instructorBio ?? FALLBACK_INSTRUCTOR_BIO,
    instructorImageUrl: info.instructorImageUrl ?? bundled?.instructorImageUrl ?? '',
    attending: scheduled?.attending,
  };
}
