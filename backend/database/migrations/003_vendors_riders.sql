
-- =========================================================
-- QUICKDELIVERY
-- MIGRATION 003: VENDORS, RIDERS AND VEHICLES
-- =========================================================

BEGIN;

-- =========================================================
-- SECTION A: VENDOR MANAGEMENT
-- =========================================================

-- ---------------------------------------------------------
-- 1. VENDOR ACCOUNTS
-- ---------------------------------------------------------

CREATE TABLE vendors.vendors (
    vendor_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    market_id UUID NOT NULL
        REFERENCES core.markets(market_id),

    owner_user_id UUID NOT NULL
        REFERENCES identity.users(user_id),

    business_name VARCHAR(200) NOT NULL,
    legal_business_name VARCHAR(200),

    business_type VARCHAR(50) NOT NULL
        CHECK (business_type IN (
            'individual',
            'sole_proprietorship',
            'partnership',
            'limited_company',
            'cooperative',
            'other'
        )),

    registration_number VARCHAR(120),
    tax_identification_number VARCHAR(120),

    business_email VARCHAR(255),
    business_phone VARCHAR(30),

    verification_status VARCHAR(25) NOT NULL DEFAULT 'pending'
        CHECK (verification_status IN (
            'pending',
            'under_review',
            'approved',
            'rejected',
            'suspended'
        )),

    operating_status VARCHAR(20) NOT NULL DEFAULT 'inactive'
        CHECK (operating_status IN (
            'inactive',
            'active',
            'temporarily_closed',
            'suspended'
        )),

    verified_at TIMESTAMPTZ,

    verified_by UUID
        REFERENCES identity.users(user_id),

    rejection_reason TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(vendor_id, market_id)
);

CREATE INDEX vendors_market_idx
ON vendors.vendors(market_id);

CREATE INDEX vendors_owner_idx
ON vendors.vendors(owner_user_id);

CREATE INDEX vendors_verification_idx
ON vendors.vendors(verification_status);


-- ---------------------------------------------------------
-- 2. VENDOR MEMBERS AND STAFF
-- ---------------------------------------------------------

CREATE TABLE vendors.vendor_members (
    membership_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    vendor_id UUID NOT NULL
        REFERENCES vendors.vendors(vendor_id),

    user_id UUID NOT NULL
        REFERENCES identity.users(user_id),

    membership_role VARCHAR(30) NOT NULL
        CHECK (membership_role IN (
            'owner',
            'manager',
            'staff',
            'accountant'
        )),

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    invited_by UUID
        REFERENCES identity.users(user_id),

    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(vendor_id, user_id)
);

CREATE INDEX vendor_members_user_idx
ON vendors.vendor_members(user_id);


-- ---------------------------------------------------------
-- 3. VENDOR BRANCHES
-- ---------------------------------------------------------

CREATE TABLE vendors.branches (
    branch_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    vendor_id UUID NOT NULL,
    market_id UUID NOT NULL,

    city_id UUID,

    branch_name VARCHAR(150) NOT NULL,

    address_line_1 VARCHAR(255) NOT NULL,
    address_line_2 VARCHAR(255),

    postal_code VARCHAR(30),

    location GEOGRAPHY(POINT, 4326),

    contact_phone VARCHAR(30),

    opening_hours JSONB NOT NULL DEFAULT '{}'::JSONB,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    FOREIGN KEY(vendor_id, market_id)
        REFERENCES vendors.vendors(vendor_id, market_id),

    FOREIGN KEY(city_id, market_id)
        REFERENCES geography.cities(city_id, market_id),

    UNIQUE(branch_id, vendor_id),
    UNIQUE(branch_id, vendor_id, market_id)
);

CREATE INDEX vendor_branches_location_idx
ON vendors.branches USING GIST(location);

CREATE INDEX vendor_branches_market_idx
ON vendors.branches(market_id);


-- ---------------------------------------------------------
-- 4. VENDOR DOCUMENTS
-- ---------------------------------------------------------

CREATE TABLE vendors.vendor_documents (
    document_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    vendor_id UUID NOT NULL
        REFERENCES vendors.vendors(vendor_id),

    document_type VARCHAR(50) NOT NULL
        CHECK (document_type IN (
            'business_registration',
            'tax_certificate',
            'owner_identity',
            'business_address_proof',
            'operating_license',
            'bank_verification',
            'other'
        )),

    document_number VARCHAR(150),

    storage_key TEXT NOT NULL,

    original_filename VARCHAR(255),
    mime_type VARCHAR(100),

    file_size_bytes BIGINT
        CHECK (
            file_size_bytes IS NULL
            OR file_size_bytes > 0
        ),

    checksum_sha256 CHAR(64),

    issuing_country CHAR(2)
        REFERENCES core.countries(country_code),

    issued_at DATE,
    expires_at DATE,

    verification_status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (verification_status IN (
            'pending',
            'approved',
            'rejected',
            'expired'
        )),

    reviewed_by UUID
        REFERENCES identity.users(user_id),

    reviewed_at TIMESTAMPTZ,

    review_notes TEXT,

    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CHECK (
        expires_at IS NULL
        OR issued_at IS NULL
        OR expires_at >= issued_at
    )
);

CREATE INDEX vendor_documents_vendor_idx
ON vendors.vendor_documents(vendor_id);


-- ---------------------------------------------------------
-- 5. VENDOR VERIFICATION HISTORY
-- ---------------------------------------------------------

CREATE TABLE vendors.verification_events (
    event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    vendor_id UUID NOT NULL
        REFERENCES vendors.vendors(vendor_id),

    previous_status VARCHAR(25),
    new_status VARCHAR(25) NOT NULL,

    action VARCHAR(30) NOT NULL
        CHECK (action IN (
            'submitted',
            'review_started',
            'approved',
            'rejected',
            'suspended',
            'reinstated',
            'resubmitted'
        )),

    reason TEXT,

    performed_by UUID
        REFERENCES identity.users(user_id),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX vendor_verification_history_idx
ON vendors.verification_events(vendor_id, created_at DESC);


-- =========================================================
-- SECTION B: RIDER MANAGEMENT
-- =========================================================

-- ---------------------------------------------------------
-- 6. RIDER PROFILES
-- ---------------------------------------------------------

CREATE TABLE riders.riders (
    rider_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL
        REFERENCES identity.users(user_id),

    market_id UUID NOT NULL
        REFERENCES core.markets(market_id),

    emergency_contact_name VARCHAR(150),
    emergency_contact_phone VARCHAR(30),

    date_of_birth DATE,

    verification_status VARCHAR(25) NOT NULL DEFAULT 'pending'
        CHECK (verification_status IN (
            'pending',
            'under_review',
            'approved',
            'rejected',
            'suspended'
        )),

    availability_status VARCHAR(20) NOT NULL DEFAULT 'offline'
        CHECK (availability_status IN (
            'offline',
            'online',
            'busy',
            'unavailable'
        )),

    average_rating NUMERIC(3,2)
        CHECK (
            average_rating IS NULL
            OR average_rating BETWEEN 0 AND 5
        ),

    total_deliveries INTEGER NOT NULL DEFAULT 0
        CHECK (total_deliveries >= 0),

    verified_at TIMESTAMPTZ,

    verified_by UUID
        REFERENCES identity.users(user_id),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(user_id, market_id),
    UNIQUE(rider_id, market_id)
);

CREATE INDEX riders_market_idx
ON riders.riders(market_id);

CREATE INDEX riders_availability_idx
ON riders.riders(market_id, availability_status);

CREATE INDEX riders_verification_idx
ON riders.riders(verification_status);


-- ---------------------------------------------------------
-- 7. RIDER VEHICLES
-- ---------------------------------------------------------

CREATE TABLE riders.vehicles (
    vehicle_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    rider_id UUID NOT NULL,
    market_id UUID NOT NULL,

    vehicle_type VARCHAR(30) NOT NULL
        CHECK (vehicle_type IN (
            'bicycle',
            'motorcycle',
            'tricycle',
            'car',
            'van',
            'truck',
            'other'
        )),

    registration_number VARCHAR(100) NOT NULL,

    make VARCHAR(100),
    model VARCHAR(100),

    manufacture_year SMALLINT
        CHECK (
            manufacture_year IS NULL
            OR manufacture_year BETWEEN 1900 AND 2100
        ),

    colour VARCHAR(50),

    maximum_load_kg NUMERIC(10,2)
        CHECK (
            maximum_load_kg IS NULL
            OR maximum_load_kg > 0
        ),

    ownership_type VARCHAR(30) NOT NULL DEFAULT 'owned'
        CHECK (ownership_type IN (
            'owned',
            'leased',
            'rented',
            'authorized'
        )),

    verification_status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (verification_status IN (
            'pending',
            'under_review',
            'approved',
            'rejected',
            'suspended'
        )),

    is_active BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    FOREIGN KEY(rider_id, market_id)
        REFERENCES riders.riders(rider_id, market_id),

    UNIQUE(vehicle_id, rider_id)
);

CREATE INDEX vehicles_rider_idx
ON riders.vehicles(rider_id);

CREATE INDEX vehicles_verification_idx
ON riders.vehicles(verification_status);

-- Prevent duplicate vehicle registration numbers
-- within the same market, regardless of letter case.

CREATE UNIQUE INDEX vehicles_market_registration_uidx
ON riders.vehicles(
    market_id,
    LOWER(registration_number)
);


-- ---------------------------------------------------------
-- 8. RIDER DOCUMENTS
-- ---------------------------------------------------------

CREATE TABLE riders.rider_documents (
    document_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    rider_id UUID NOT NULL,

    vehicle_id UUID,

    document_type VARCHAR(50) NOT NULL
        CHECK (document_type IN (
            'government_identity',
            'passport',
            'drivers_license',
            'vehicle_registration',
            'vehicle_ownership',
            'vehicle_authorization',
            'insurance_certificate',
            'roadworthiness_certificate',
            'proof_of_address',
            'other'
        )),

    document_number VARCHAR(150),

    issuing_country CHAR(2)
        REFERENCES core.countries(country_code),

    storage_key TEXT NOT NULL,

    original_filename VARCHAR(255),
    mime_type VARCHAR(100),

    file_size_bytes BIGINT
        CHECK (
            file_size_bytes IS NULL
            OR file_size_bytes > 0
        ),

    checksum_sha256 CHAR(64),

    issued_at DATE,
    expires_at DATE,

    verification_status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (verification_status IN (
            'pending',
            'approved',
            'rejected',
            'expired'
        )),

    reviewed_by UUID
        REFERENCES identity.users(user_id),

    reviewed_at TIMESTAMPTZ,

    review_notes TEXT,

    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Every document must belong to an existing rider.
    FOREIGN KEY(rider_id)
        REFERENCES riders.riders(rider_id),

    -- If a vehicle is specified, it must belong to this rider.
    -- If vehicle_id is NULL, the document is rider-level.
    FOREIGN KEY(vehicle_id, rider_id)
        REFERENCES riders.vehicles(vehicle_id, rider_id),

    CHECK (
        expires_at IS NULL
        OR issued_at IS NULL
        OR expires_at >= issued_at
    )
);

CREATE INDEX rider_documents_rider_idx
ON riders.rider_documents(rider_id);

CREATE INDEX rider_documents_vehicle_idx
ON riders.rider_documents(vehicle_id);

CREATE INDEX rider_documents_verification_idx
ON riders.rider_documents(verification_status);


-- ---------------------------------------------------------
-- 9. RIDER VERIFICATION HISTORY
-- ---------------------------------------------------------

CREATE TABLE riders.verification_events (
    event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    rider_id UUID NOT NULL
        REFERENCES riders.riders(rider_id),

    previous_status VARCHAR(25),
    new_status VARCHAR(25) NOT NULL,

    action VARCHAR(30) NOT NULL
        CHECK (action IN (
            'submitted',
            'review_started',
            'approved',
            'rejected',
            'suspended',
            'reinstated',
            'resubmitted'
        )),

    reason TEXT,

    performed_by UUID
        REFERENCES identity.users(user_id),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX rider_verification_history_idx
ON riders.verification_events(rider_id, created_at DESC);


-- ---------------------------------------------------------
-- 10. VEHICLE VERIFICATION HISTORY
-- ---------------------------------------------------------

CREATE TABLE riders.vehicle_verification_events (
    event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    vehicle_id UUID NOT NULL
        REFERENCES riders.vehicles(vehicle_id),

    previous_status VARCHAR(20),
    new_status VARCHAR(20) NOT NULL,

    reason TEXT,

    performed_by UUID
        REFERENCES identity.users(user_id),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX vehicle_verification_history_idx
ON riders.vehicle_verification_events(vehicle_id, created_at DESC);


-- =========================================================
-- END OF MIGRATION 003
-- =========================================================

COMMIT;
