-- Delete leaked preview_add applied-discount rows for the payer. These get
-- staged by the START preview (on its preview_add memberships) AND by the
-- discount-ADD preview (on a REAL applied membership), so scope by the
-- DISCOUNT row's OWN preview_add status across ALL of the payer's memberships
-- — not just preview_add memberships — else a crashed discount-add preview's
-- rows on a real membership would leak forever. FK-first: this runs before the
-- preview_add membership delete (member_memberships_sweep_preview.sql), and a
-- preview_add membership's discounts are themselves preview_add, so they are
-- covered here too (the membership delete then RESTRICTs on nothing).
DELETE FROM member_membership_applied_discounts_unfiltered
WHERE stripe_sync_status = 'preview_add'
  AND item_id IN (
      SELECT item_id
      FROM member_memberships_unfiltered
      WHERE paid_by_member_id = :payer_member_id
  )
RETURNING applied_discount_id, item_id
