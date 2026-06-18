-- Relax refund_has_refund_id to allow cash refunds (no stripe_refund_id needed),
-- mirroring the existing payment_has_charge_id CHECK which already permits
-- payment_method_type = 'cash'. A cash refund is the mirror of a cash payment:
-- neither carries a Stripe id by design.
--
-- Hand-authored — `supabase db diff` cannot be used here (see Database/CLAUDE.md).

ALTER TABLE member_charges DROP CONSTRAINT refund_has_refund_id;
ALTER TABLE member_charges ADD CONSTRAINT refund_has_refund_id
    CHECK (kind <> 'refund' OR stripe_refund_id IS NOT NULL OR payment_method_type = 'cash');
