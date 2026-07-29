// Ports MobileApp/lib/features/home/presentation/widgets/class_schedule/
// class_item/class_item_layout.dart.
//
// PRESENTATION ONLY. Every value renders the identical element set — title,
// time, instructor, attendee count, thumbnail (and the booked mark on the page
// that carries one). Only arrangement and prominence change, which is what
// keeps `home_format` an arrangement-only choice rather than a feature switch.

/** How one class row is drawn. `ClassItemLayout`. */
export type ClassItemLayout =
  /** Shipped today: text left, 16:9 thumbnail right, rule beneath. */
  | 'textLeftThumbRight'
  /** Full-width 16:9 image on top, meta beneath it. */
  | 'imageTop'
  /** Time hoisted into a leading gutter against a vertical rule; small square thumb. */
  | 'spine'
  /** Compact row: small thumb leading, tight meta, hairline rule. */
  | 'dense'
  /** Raised card: 4:3 image on top, meta padded beneath. Grid cells. */
  | 'card';
