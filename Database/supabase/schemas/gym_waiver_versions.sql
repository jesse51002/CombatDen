-- Versions of a waiver's text — conditionally immutable.
--
-- Editing a body while the current version has 0 signatures updates that row
-- IN PLACE (the backend, at service_role). Once a member has signed a version
-- it is frozen: a further edit PUBLISHES a new version row (version_number
-- bumped) and re-points current_version_id. Clients can never write version
-- rows (REVOKE UPDATE, DELETE in the access rules), and a signed version is
-- never mutated or deleted, so a signature bound to a version always reproduces
-- the exact wording the member agreed to. content_hash is a sha256 of the body
-- computed by the backend at publish time; member_waiver_signatures copies it so
-- the signed text is provable even if hashing/normalization rules change later.
CREATE TABLE gym_waiver_versions (
    version_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    waiver_id UUID NOT NULL CONSTRAINT fk_waiver_version_waiver REFERENCES gym_waivers(waiver_id),
    gym_id UUID NOT NULL CONSTRAINT fk_waiver_version_gym REFERENCES gyms(gym_id),
    version_number INTEGER NOT NULL CHECK (version_number > 0),
    body TEXT NOT NULL CHECK (body <> ''),
    content_hash VARCHAR NOT NULL CHECK (content_hash <> ''),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (version_id),
    UNIQUE (version_id, gym_id),
    UNIQUE (waiver_id, version_number),
    CONSTRAINT fk_waiver_version_waiver_gym
        FOREIGN KEY (waiver_id, gym_id)
        REFERENCES gym_waivers (waiver_id, gym_id)
);

CREATE INDEX idx_gym_waiver_versions_waiver ON gym_waiver_versions (waiver_id);

-- Deferred current-version FK on gym_waivers: the target table now exists.
-- gym_waivers is created with current_version_id NULL, its first version is
-- inserted, then current_version_id is set — all in one backend transaction.
ALTER TABLE gym_waivers
    ADD CONSTRAINT fk_waiver_current_version
    FOREIGN KEY (current_version_id) REFERENCES gym_waiver_versions(version_id);
