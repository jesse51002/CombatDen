DELETE FROM member_invoice_line_items
WHERE item_id IN (
    SELECT item_id
    FROM member_memberships_unfiltered
    WHERE member_id = :id
)
