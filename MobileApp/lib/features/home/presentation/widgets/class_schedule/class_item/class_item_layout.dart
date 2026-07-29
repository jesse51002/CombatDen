/// How one class row is drawn.
///
/// Presentation only. Every value renders the identical element set —
/// title, time, instructor, attendee count, booked mark, thumbnail and
/// the tap into class detail. Only arrangement and prominence change,
/// which is what keeps `home_format` an arrangement-only choice.
enum ClassItemLayout {
  /// Shipped today: text left, 16:9 thumbnail right, rule beneath.
  textLeftThumbRight,

  /// Full-width 16:9 image on top, meta beneath it.
  imageTop,

  /// Time hoisted into a leading gutter against a vertical rule; the
  /// thumbnail demotes to a small square.
  spine,

  /// Compact row: small thumb leading, tight meta, hairline rule.
  dense,

  /// Raised card: 4:3 image on top, meta padded beneath. Grid cells.
  card,
}
