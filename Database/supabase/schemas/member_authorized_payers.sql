-- Authorized payers — the AUTHORIZATION layer: who may pay for whom.
--
-- A member (member_id, the one being paid for) may have MANY authorized payers
-- (payer_member_id, who is allowed to bill that member's memberships), and any
-- member may be an authorized payer for others while also having their own. This
-- replaces the single-parent members.account_linked_to_id link — multi-level
-- composes cleanly because billing is per-membership.
--
-- This is NOT the billing key. member_memberships.paid_by_member_id is who
-- actually pays a given membership; a row here only says "X is ALLOWED to pay
-- for Y". A self-paying member needs no row (the CHECK forbids member = payer).
--
-- Each authorization is gated by a signed waiver: signature_id points at the
-- member_waiver_signatures row the payer signed to create this link. The
-- signature log is the immutable audit trail; this table is the live
-- relationship — unlinking DELETEs the row while the signature record persists.
-- Backend-managed (service_role): created by the link endpoint after the waiver
-- is signed, deleted on unlink. Not Stripe-gated (no stripe_* column).
--
-- Loads after members + member_waiver_signatures (see config.toml schema_paths)
-- so all referenced tables exist and the FKs can be declared inline.
CREATE TABLE member_authorized_payers (
    member_id UUID NOT NULL,
    payer_member_id UUID NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_authpayer_gym REFERENCES gyms(gym_id),
    signature_id UUID NOT NULL
        CONSTRAINT fk_authpayer_signature
        REFERENCES member_waiver_signatures(signature_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (member_id, payer_member_id),

    -- A member never authorizes themselves — self-pay needs no row.
    CONSTRAINT chk_authpayer_distinct CHECK (member_id <> payer_member_id),

    CONSTRAINT fk_authpayer_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id),

    CONSTRAINT fk_authpayer_payer_gym
        FOREIGN KEY (payer_member_id, gym_id)
        REFERENCES members (member_id, gym_id)
);

-- Both directions are read: "who may pay for me" (member_id) and "who am I
-- authorized to pay for" (payer_member_id).
CREATE INDEX idx_authpayer_member
    ON member_authorized_payers (member_id, gym_id);
CREATE INDEX idx_authpayer_payer
    ON member_authorized_payers (payer_member_id, gym_id);
