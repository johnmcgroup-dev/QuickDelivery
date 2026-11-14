
-- =========================================================
-- QUICKDELIVERY
-- MIGRATION 001: GLOBAL FOUNDATION
-- PostgreSQL 17+ / PostGIS
-- =========================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS identity;
CREATE SCHEMA IF NOT EXISTS geography;
CREATE SCHEMA IF NOT EXISTS vendors;
CREATE SCHEMA IF NOT EXISTS riders;
CREATE SCHEMA IF NOT EXISTS security;

-- ---------------------------------------------------------
-- 1. CURRENCIES
-- ---------------------------------------------------------

CREATE TABLE core.currencies (
    currency_code CHAR(3) PRIMARY KEY,
    currency_name VARCHAR(100) NOT NULL,
    currency_symbol VARCHAR(10),
    minor_unit_exponent SMALLINT NOT NULL
        CHECK (minor_unit_exponent BETWEEN 0 AND 3),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO core.currencies
(currency_code, currency_name, currency_symbol, minor_unit_exponent)
VALUES
('NGN', 'Nigerian Naira', '₦', 2),
('GHS', 'Ghanaian Cedi', 'GH₵', 2),
('GBP', 'British Pound', '£', 2),
('USD', 'US Dollar', '$', 2),
('EUR', 'Euro', '€', 2),
('KES', 'Kenyan Shilling', 'KSh', 2),
('ZAR', 'South African Rand', 'R', 2),
('JPY', 'Japanese Yen', '¥', 0),
('KWD', 'Kuwaiti Dinar', 'KD', 3)
ON CONFLICT (currency_code) DO NOTHING;

-- ---------------------------------------------------------
-- 2. COUNTRIES
-- ---------------------------------------------------------

CREATE TABLE core.countries (
    country_code CHAR(2) PRIMARY KEY,
    country_name VARCHAR(120) NOT NULL,
    default_currency CHAR(3) NOT NULL
        REFERENCES core.currencies(currency_code),
    calling_code VARCHAR(10),
    default_timezone VARCHAR(100) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO core.countries
(country_code, country_name, default_currency,
 calling_code, default_timezone)
VALUES
('NG', 'Nigeria', 'NGN', '+234', 'Africa/Lagos'),
('GH', 'Ghana', 'GHS', '+233', 'Africa/Accra'),
('GB', 'United Kingdom', 'GBP', '+44', 'Europe/London'),
('US', 'United States', 'USD', '+1', 'America/New_York'),
('DE', 'Germany', 'EUR', '+49', 'Europe/Berlin'),
('KE', 'Kenya', 'KES', '+254', 'Africa/Nairobi'),
('ZA', 'South Africa', 'ZAR', '+27', 'Africa/Johannesburg'),
('JP', 'Japan', 'JPY', '+81', 'Asia/Tokyo'),
('KW', 'Kuwait', 'KWD', '+965', 'Asia/Kuwait')
ON CONFLICT (country_code) DO NOTHING;

-- ---------------------------------------------------------
-- 3. INTERNATIONAL MARKETS
-- A market is an activated commercial operating environment.
-- ---------------------------------------------------------

CREATE TABLE core.markets (
    market_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    country_code CHAR(2) NOT NULL
        REFERENCES core.countries(country_code),

    market_code VARCHAR(30) NOT NULL UNIQUE,
    market_name VARCHAR(150) NOT NULL,

    settlement_currency CHAR(3) NOT NULL
        REFERENCES core.currencies(currency_code),

    timezone VARCHAR(100) NOT NULL,
    default_locale VARCHAR(20) NOT NULL DEFAULT 'en',

    status VARCHAR(20) NOT NULL DEFAULT 'planned'
        CHECK (status IN ('planned', 'active', 'suspended')),

    configuration JSONB NOT NULL DEFAULT '{}'::JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(country_code, market_name)
);

CREATE INDEX markets_country_idx
ON core.markets(country_code);

CREATE INDEX markets_status_idx
ON core.markets(status);

-- ---------------------------------------------------------
-- 4. MARKET SUPPORTED CURRENCIES
-- ---------------------------------------------------------

CREATE TABLE core.market_currencies (
    market_id UUID NOT NULL
        REFERENCES core.markets(market_id),

    currency_code CHAR(3) NOT NULL
        REFERENCES core.currencies(currency_code),

    is_settlement_currency BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    PRIMARY KEY(market_id, currency_code)
);

-- ---------------------------------------------------------
-- 5. MARKET LANGUAGES
-- ---------------------------------------------------------

CREATE TABLE core.market_locales (
    market_id UUID NOT NULL
        REFERENCES core.markets(market_id),

    locale_code VARCHAR(20) NOT NULL,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    PRIMARY KEY(market_id, locale_code)
);

-- ---------------------------------------------------------
-- 6. GEOGRAPHICAL OPERATING LOCATIONS
-- ---------------------------------------------------------

CREATE TABLE geography.cities (
    city_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    market_id UUID NOT NULL
        REFERENCES core.markets(market_id),

    city_name VARCHAR(150) NOT NULL,
    state_region VARCHAR(150),

    center_location GEOGRAPHY(POINT, 4326),

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(market_id, city_name, state_region)
    UNIQUE(city_id, market_id)
);

CREATE INDEX cities_location_idx
ON geography.cities
USING GIST(center_location);

-- ---------------------------------------------------------
-- 7. SERVICE ZONES
-- ---------------------------------------------------------

CREATE TABLE geography.service_zones (
    zone_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    market_id UUID NOT NULL
        REFERENCES core.markets(market_id),

    city_id UUID
        REFERENCES geography.cities(city_id),

    zone_name VARCHAR(150) NOT NULL,

    boundary GEOGRAPHY(MULTIPOLYGON, 4326),

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(market_id, zone_name)
);

CREATE INDEX service_zones_boundary_idx
ON geography.service_zones
USING GIST(boundary);

-- ---------------------------------------------------------
-- 8. GLOBAL APPLICATION CONFIGURATION
-- ---------------------------------------------------------

CREATE TABLE core.platform_settings (
    setting_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    setting_key VARCHAR(150) NOT NULL UNIQUE,
    setting_value JSONB NOT NULL,

    description TEXT,

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Initial global settings

INSERT INTO core.platform_settings
(setting_key, setting_value, description)
VALUES
('platform_name', '"QuickDelivery"',
 'Application name'),

('default_order_currency_policy', '"market_settlement_currency"',
 'Orders use the selected market settlement currency'),

('registration_enabled', 'true',
 'Allow new user registrations'),

('vendor_approval_required', 'true',
 'Vendor approval is required'),

('rider_approval_required', 'true',
 'Rider approval is required');

COMMIT;
