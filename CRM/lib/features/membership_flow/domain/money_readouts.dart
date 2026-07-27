/// The only arithmetic a purchase surface does on money: what is charged
/// today, whether that lands as two charges, and whether it is a part period.
///
/// Every figure comes straight off the SERVER's preview — a price is never
/// derived from a plan row here. The functions are pure over
/// `(preview, prorationBehavior)` so both a surface that pins
/// `prorate_to_anchor` (the kiosk) and one that lets staff choose (the wizard)
/// read the same numbers through the same code.
library;

import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';

/// The due-now invoice as the CHOICE dictates: the fetched proration when
/// prorating, otherwise null.
///
/// The preview is always fetched at `prorate_to_anchor`, so `preview.dueNow`
/// holds the proration whatever was chosen; `no_charge` bills nothing now
/// (definitionally), so its due-now line disappears while the recurring and
/// one-time figures stay identical. Every readout below goes through this, so
/// a surface offering `no_charge` cannot overstate today's charge.
PreviewInvoice? effectiveDueNow(
  MemberMembershipsStartPreview? preview,
  ProrationBehavior prorationBehavior,
) =>
    prorationBehavior == ProrationBehavior.prorateToAnchor
        ? preview?.dueNow
        : null;

/// The one combined amount charged today, in minor units: the one-time invoice
/// plus the recurring amount due now.
int dueTodayMinorUnits(
  MemberMembershipsStartPreview? preview,
  ProrationBehavior prorationBehavior,
) =>
    (preview?.oneTime?.total ?? 0) +
    (effectiveDueNow(preview, prorationBehavior)?.total ?? 0);

/// True when the payer's statement will show TWO charges today — a non-zero
/// one-time invoice AND a non-zero recurring amount due now. It tests the
/// AMOUNTS, never nullness and never `preview.recurring`: a $0 one-time line is
/// a present invoice with nothing on it, not a second charge.
bool chargedTwiceToday(
  MemberMembershipsStartPreview? preview,
  ProrationBehavior prorationBehavior,
) =>
    (preview?.oneTime?.total ?? 0) > 0 &&
    (effectiveDueNow(preview, prorationBehavior)?.total ?? 0) > 0;

/// True when today's charge is a PART period. Read off the lines' own
/// `is_proration`, never inferred from "the two figures differ": a false
/// proration claim misstates the member's money.
bool chargedProrated(
  MemberMembershipsStartPreview? preview,
  ProrationBehavior prorationBehavior,
) {
  for (final line in [
    ...?preview?.oneTime?.lines,
    ...?effectiveDueNow(preview, prorationBehavior)?.lines,
  ]) {
    if (line.isProration) return true;
  }
  return false;
}

/// The billing-period end a part-period charge runs up to, and the day the
/// full amount first bills — the preview's own `next_payment_date`.
DateTime? prorationUntil(
  MemberMembershipsStartPreview? preview,
  ProrationBehavior prorationBehavior,
) =>
    effectiveDueNow(preview, prorationBehavior)?.nextPaymentAt ??
    preview?.recurring?.nextPaymentAt;

/// The currency every figure is rendered in — whichever half of the preview
/// exists, in the CRM's own order of preference.
String previewCurrency(
  MemberMembershipsStartPreview? preview,
  ProrationBehavior prorationBehavior,
) =>
    preview?.oneTime?.currency ??
    effectiveDueNow(preview, prorationBehavior)?.currency ??
    preview?.recurring?.currency ??
    'usd';
