
-- =========================================================
-- QUICKDELIVERY
-- MIGRATION 002: IDENTITY AND ACCESS CONTROL
-- =========================================================

BEGIN;

-- ---------------------------------------------------------
-- 1. GLOBAL USERS
-- ---------------------------------------------------------

CREATE TABLE identity.users (
    user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    email VARCHAR(255),
    phone_number VARCHAR(30),

    password_hash TEXT,

    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,

    profile_image_key TEXT,

    account_status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (account_status IN (
            'pending',
            'active',
            'suspended',
            'closed'
        )),

    email_verified_at TIMESTAMPTZ,
    phone_verified_at TIMESTAMPTZ,

    last_login_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CHECK (
        email IS NOT NULL OR phone_number IS NOT NULL
    )
);

CREATE UNIQUE INDEX users_email_unique
ON identity.users(LOWER(email))
WHERE email IS NOT NULL;

CREATE UNIQUE INDEX users_phone_unique
ON identity.users(phone_number)
WHERE phone_number IS NOT NULL;

-- ---------------------------------------------------------
-- 2. ROLES
-- ---------------------------------------------------------

CREATE TABLE identity.roles (
    role_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    role_code VARCHAR(50) NOT NULL UNIQUE,
    role_name VARCHAR(100) NOT NULL,

    scope_type VARCHAR(20) NOT NULL
        CHECK (scope_type IN (
            'global',
            'market',
            'vendor',
            'branch'
        )),

    description TEXT,

    is_system_role BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO identity.roles
(role_code, role_name, scope_type, description)
VALUES
('SUPER_ADMIN', 'Super Administrator', 'global',
 'Full platform control'),

('ADMIN', 'Administrator', 'market',
 'Market-level operational management'),

('CUSTOMER', 'Customer', 'global',
 'Marketplace customer'),

('VENDOR_OWNER', 'Vendor Owner', 'vendor',
 'Owns and manages a vendor account'),

('VENDOR_MANAGER', 'Vendor Manager', 'vendor',
 'Manages vendor operations'),

('VENDOR_STAFF', 'Vendor Staff', 'branch',
 'Branch-level vendor operations'),

('RIDER', 'Delivery Rider', 'market',
 'Approved delivery rider');

-- ---------------------------------------------------------
-- 3. PERMISSIONS
-- ---------------------------------------------------------

CREATE TABLE identity.permissions (
    permission_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    permission_code VARCHAR(100) NOT NULL UNIQUE,
    permission_name VARCHAR(150) NOT NULL,

    module VARCHAR(60) NOT NULL,
    description TEXT
);

INSERT INTO identity.permissions
(permission_code, permission_name, module)
VALUES

('users.read', 'View users', 'identity'),
('users.manage', 'Manage users', 'identity'),

('markets.read', 'View markets', 'markets'),
('markets.manage', 'Manage markets', 'markets'),

('vendors.read', 'View vendors', 'vendors'),
('vendors.manage', 'Manage vendors', 'vendors'),
('vendors.verify', 'Verify vendors', 'vendors'),

('riders.read', 'View riders', 'riders'),
('riders.manage', 'Manage riders', 'riders'),
('riders.verify', 'Verify riders', 'riders'),

('products.read', 'View products', 'catalog'),
('products.manage', 'Manage products', 'catalog'),

('inventory.read', 'View inventory', 'inventory'),
('inventory.manage', 'Manage inventory', 'inventory'),

('orders.read', 'View orders', 'sales'),
('orders.manage', 'Manage orders', 'sales'),

('deliveries.read', 'View deliveries', 'logistics'),
('deliveries.manage', 'Manage deliveries', 'logistics'),

('payments.read', 'View payments', 'payments'),
('payments.manage', 'Manage payments', 'payments'),

('commissions.manage', 'Manage commissions', 'finance'),
('payouts.manage', 'Manage payouts', 'finance'),
('reports.read', 'View financial reports', 'finance'),

('settings.manage', 'Manage platform settings', 'system');

-- ---------------------------------------------------------
-- 4. ROLE PERMISSIONS
-- ---------------------------------------------------------

CREATE TABLE identity.role_permissions (
    role_id UUID NOT NULL
        REFERENCES identity.roles(role_id)
        ON DELETE CASCADE,

    permission_id UUID NOT NULL
        REFERENCES identity.permissions(permission_id)
        ON DELETE CASCADE,

    PRIMARY KEY(role_id, permission_id)
);

-- Super Admin receives all currently registered permissions.

INSERT INTO identity.role_permissions
(role_id, permission_id)

SELECT r.role_id, p.permission_id
FROM identity.roles r
CROSS JOIN identity.permissions p
WHERE r.role_code = 'SUPER_ADMIN';

-- ---------------------------------------------------------
-- 5. ROLE ASSIGNMENTS
-- ---------------------------------------------------------

CREATE TABLE identity.role_assignments (
    assignment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL
        REFERENCES identity.users(user_id),

    role_id UUID NOT NULL
        REFERENCES identity.roles(role_id),

    market_id UUID
        REFERENCES core.markets(market_id),

    scope_type VARCHAR(20) NOT NULL
        CHECK (scope_type IN (
            'global',
            'market',
            'vendor',
            'branch'
        )),

    scope_id UUID,

    assigned_by UUID
        REFERENCES identity.users(user_id),

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    expires_at TIMESTAMPTZ,

    CHECK (
        (scope_type = 'global'
            AND scope_id IS NULL
            AND market_id IS NULL)
        OR
        (scope_type = 'market'
            AND scope_id = market_id
            AND market_id IS NOT NULL)
        OR
        (scope_type IN ('vendor', 'branch')
            AND scope_id IS NOT NULL
            AND market_id IS NOT NULL)
    ),

    CHECK (
        expires_at IS NULL OR expires_at > assigned_at
    )
);

CREATE INDEX role_assignments_user_idx
ON identity.role_assignments(user_id, is_active);

CREATE INDEX role_assignments_scope_idx
ON identity.role_assignments(scope_type, scope_id);

-- Prevent duplicate active global assignments.

CREATE UNIQUE INDEX role_assignment_global_unique
ON identity.role_assignments(user_id, role_id)
WHERE scope_type = 'global' AND is_active = TRUE;

CREATE UNIQUE INDEX role_assignment_scoped_unique
ON identity.role_assignments(user_id, role_id, scope_type, scope_id)
WHERE scope_type <> 'global' AND is_active = TRUE;

-- ---------------------------------------------------------
-- 6. USER AUTHENTICATION SESSIONS
-- ---------------------------------------------------------

CREATE TABLE identity.user_sessions (
    session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL
        REFERENCES identity.users(user_id),

    refresh_token_hash TEXT NOT NULL UNIQUE,

    device_name VARCHAR(150),
    device_type VARCHAR(50),

    ip_address INET,
    user_agent TEXT,

    expires_at TIMESTAMPTZ NOT NULL,

    revoked_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX user_sessions_user_idx
ON identity.user_sessions(user_id);

-- ---------------------------------------------------------
-- 7. OTP CHALLENGES
-- ---------------------------------------------------------

CREATE TABLE identity.otp_challenges (
    challenge_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID
        REFERENCES identity.users(user_id),

    destination VARCHAR(255) NOT NULL,

    challenge_type VARCHAR(30) NOT NULL
        CHECK (challenge_type IN (
            'email_verification',
            'phone_verification',
            'login',
            'password_reset'
        )),

    code_hash TEXT NOT NULL,

    attempts SMALLINT NOT NULL DEFAULT 0,
    max_attempts SMALLINT NOT NULL DEFAULT 5,

    expires_at TIMESTAMPTZ NOT NULL,

    verified_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CHECK (attempts >= 0),
    CHECK (max_attempts > 0)
);

CREATE INDEX otp_destination_idx
ON identity.otp_challenges(destination, challenge_type);

-- ---------------------------------------------------------
-- 8. AUTHENTICATION PROVIDERS
-- ---------------------------------------------------------

CREATE TABLE identity.external_auth_accounts (
    external_account_id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL
        REFERENCES identity.users(user_id),

    provider VARCHAR(50) NOT NULL,
    provider_subject VARCHAR(255) NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(provider, provider_subject)
);

COMMIT;
