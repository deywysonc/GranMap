CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE IF NOT EXISTS courses (
    id BIGSERIAL PRIMARY KEY,
    name CITEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS professors (
    id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email CITEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS rooms (
    id BIGSERIAL PRIMARY KEY,
    poi_id TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    floor INTEGER NOT NULL DEFAULT 0,
    building TEXT NOT NULL DEFAULT 'Gran',
    geom geometry(PointZ)
);

CREATE TABLE IF NOT EXISTS subjects (
    id BIGSERIAL PRIMARY KEY,
    course_id BIGINT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    name CITEXT NOT NULL,
    UNIQUE(course_id, name)
);

CREATE TABLE IF NOT EXISTS academic_groups (
    id BIGSERIAL PRIMARY KEY,
    course_id BIGINT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    semester INTEGER NOT NULL,
    name CITEXT NOT NULL,
    UNIQUE(course_id, semester, name)
);

CREATE TABLE IF NOT EXISTS schedules (
    id BIGSERIAL PRIMARY KEY,
    course_id BIGINT NOT NULL REFERENCES courses(id),
    semester INTEGER NOT NULL,
    group_name CITEXT NOT NULL,
    subject TEXT NOT NULL,
    professor_id BIGINT REFERENCES professors(id),
    room_id BIGINT NOT NULL REFERENCES rooms(id),
    weekday TEXT NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    subject_id BIGINT REFERENCES subjects(id),
    group_id BIGINT REFERENCES academic_groups(id)
);

CREATE TABLE IF NOT EXISTS users (
    id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email CITEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    password_salt TEXT NOT NULL DEFAULT '',
    password_algorithm TEXT NOT NULL DEFAULT 'argon2id',
    course_name TEXT NOT NULL,
    semester INTEGER NOT NULL,
    group_name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'student',
    reputation INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS sessions (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS user_favorites (
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    poi_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY(user_id, poi_id)
);

CREATE TABLE IF NOT EXISTS navigation_history (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    poi_id TEXT NOT NULL,
    poi_name TEXT NOT NULL,
    visited_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS proposals (
    id BIGSERIAL PRIMARY KEY,
    author_name TEXT NOT NULL,
    author_user_id BIGINT REFERENCES users(id),
    subject TEXT NOT NULL,
    from_room TEXT NOT NULL,
    to_room TEXT NOT NULL,
    reason TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'unverified',
    official_priority SMALLINT NOT NULL DEFAULT 0,
    reputation_awarded SMALLINT NOT NULL DEFAULT 0,
    moderation_note TEXT NOT NULL DEFAULT '',
    resolved_by_user_id BIGINT REFERENCES users(id),
    resolved_at TIMESTAMPTZ,
    applied_at TIMESTAMPTZ,
    applied_schedule_id BIGINT REFERENCES schedules(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    idempotency_key TEXT
);

CREATE TABLE IF NOT EXISTS votes (
    id BIGSERIAL PRIMARY KEY,
    proposal_id BIGINT NOT NULL REFERENCES proposals(id) ON DELETE CASCADE,
    voter_name TEXT NOT NULL,
    voter_user_id BIGINT REFERENCES users(id),
    agrees SMALLINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS audit_log (
    id BIGSERIAL PRIMARY KEY,
    action TEXT NOT NULL,
    details TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS map_versions (
    id BIGSERIAL PRIMARY KEY,
    version TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    schema_version INTEGER NOT NULL DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'draft',
    map_json JSONB NOT NULL,
    checksum TEXT NOT NULL,
    notes TEXT NOT NULL DEFAULT '',
    created_by_user_id BIGINT REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS route_closures (
    id BIGSERIAL PRIMARY KEY,
    edge_id TEXT NOT NULL,
    floor INTEGER NOT NULL,
    reason TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    starts_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ends_at TIMESTAMPTZ,
    created_by_user_id BIGINT NOT NULL REFERENCES users(id),
    resolved_by_user_id BIGINT REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS positioning_anchors (
    id BIGSERIAL PRIMARY KEY,
    anchor_code TEXT NOT NULL UNIQUE,
    node_id TEXT NOT NULL,
    kind TEXT NOT NULL DEFAULT 'qr',
    x DOUBLE PRECISION NOT NULL,
    y DOUBLE PRECISION NOT NULL,
    z DOUBLE PRECISION NOT NULL,
    floor INTEGER NOT NULL,
    heading DOUBLE PRECISION NOT NULL DEFAULT 0,
    enabled SMALLINT NOT NULL DEFAULT 1,
    metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    geom geometry(PointZ),
    created_by_user_id BIGINT REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS magnetic_fingerprints (
    id BIGSERIAL PRIMARY KEY,
    map_version_id BIGINT REFERENCES map_versions(id),
    x DOUBLE PRECISION NOT NULL,
    y DOUBLE PRECISION NOT NULL,
    z DOUBLE PRECISION NOT NULL,
    floor INTEGER NOT NULL,
    magnetic_x DOUBLE PRECISION NOT NULL,
    magnetic_y DOUBLE PRECISION NOT NULL,
    magnetic_z DOUBLE PRECISION NOT NULL,
    device_model TEXT NOT NULL DEFAULT '',
    quality DOUBLE PRECISION NOT NULL DEFAULT 0,
    geom geometry(PointZ),
    captured_by_user_id BIGINT REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS auth_events (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES users(id),
    email CITEXT NOT NULL DEFAULT '',
    event TEXT NOT NULL,
    ip_hash TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS notifications (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    data_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS rate_limit_buckets (
    key TEXT PRIMARY KEY,
    window_start BIGINT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS account_tokens (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    purpose TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_sessions_token_hash ON sessions(token_hash);
CREATE INDEX IF NOT EXISTS idx_sessions_user_active ON sessions(user_id, expires_at, revoked_at);
CREATE INDEX IF NOT EXISTS idx_history_user_time ON navigation_history(user_id, visited_at DESC);
CREATE INDEX IF NOT EXISTS idx_proposals_status_created ON proposals(status, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_proposals_author_idempotency ON proposals(author_user_id, idempotency_key) WHERE author_user_id IS NOT NULL AND idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_votes_proposal ON votes(proposal_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_votes_proposal_user ON votes(proposal_id, voter_user_id) WHERE voter_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_schedules_room_time ON schedules(weekday, room_id, start_time, end_time);
CREATE INDEX IF NOT EXISTS idx_schedules_professor_time ON schedules(weekday, professor_id, start_time, end_time);
CREATE INDEX IF NOT EXISTS idx_subjects_course ON subjects(course_id, name);
CREATE INDEX IF NOT EXISTS idx_groups_course ON academic_groups(course_id, semester, name);
CREATE INDEX IF NOT EXISTS idx_map_versions_status ON map_versions(status, published_at DESC);
CREATE INDEX IF NOT EXISTS idx_route_closures_active ON route_closures(status, starts_at, ends_at);
CREATE INDEX IF NOT EXISTS idx_anchors_floor ON positioning_anchors(floor, enabled);
CREATE INDEX IF NOT EXISTS idx_fingerprints_floor ON magnetic_fingerprints(floor, map_version_id);
CREATE INDEX IF NOT EXISTS idx_auth_events_email_time ON auth_events(email, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_user_time ON notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON notifications(user_id, read_at, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_account_tokens_lookup ON account_tokens(token_hash, purpose, expires_at, used_at);
CREATE INDEX IF NOT EXISTS idx_rooms_geom ON rooms USING GIST(geom);
CREATE INDEX IF NOT EXISTS idx_anchors_geom ON positioning_anchors USING GIST(geom);
CREATE INDEX IF NOT EXISTS idx_fingerprints_geom ON magnetic_fingerprints USING GIST(geom);
