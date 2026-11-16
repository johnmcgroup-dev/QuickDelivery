
BEGIN;

CREATE SCHEMA IF NOT EXISTS logistics;


-- =========================================================
-- 1. COURIER COMPANIES
-- Global registry of supported delivery providers.
-- =========================================================

CREATE TABLE logistics.courier_companies (
    carrier_company_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    company_code VARCHAR(40) NOT NULL UNIQUE,
    company_name VARCHAR(180) NOT NULL,

    company_type VARCHAR(30) NOT NULL DEFAULT 'COURIER',

    website_url TEXT,
    support_email VARCHAR(255),
    support_phone VARCHAR(40),

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CHECK(company_type IN (
        'COURIER',
        'POSTAL',
        'LOCAL_LOGISTICS',
        'FREIGHT'
    ))
);

-- Register the initial international providers.
-- Actual API access must be configured separately.

INSERT INTO logistics.courier_companies
    (company_code, company_name, company_type, website_url)
VALUES
    ('DHL', 'DHL', 'COURIER', 'https://www.dhl.com'),
    ('UPS', 'UPS', 'COURIER', 'https://www.ups.com'),
    ('FEDEX', 'FedEx', 'COURIER', 'https://www.fedex.com')
ON CONFLICT (company_code) DO NOTHING;


-- =========================================================
-- 2. COURIER SERVICES
-- Different services offered by each courier.
-- Examples: Express, Standard, Economy.
-- =========================================================

CREATE TABLE logistics.courier_services (
    service_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    carrier_company_id UUID NOT NULL
        REFERENCES logistics.courier_companies(carrier_company_id),

    service_code VARCHAR(80) NOT NULL,
    service_name VARCHAR(180) NOT NULL,

    service_description TEXT,

    delivery_speed VARCHAR(30),

    supports_domestic BOOLEAN NOT NULL DEFAULT TRUE,
    supports_international BOOLEAN NOT NULL DEFAULT FALSE,

    supports_tracking BOOLEAN NOT NULL DEFAULT TRUE,
    supports_shipping_labels BOOLEAN NOT NULL DEFAULT FALSE,
    supports_pickup BOOLEAN NOT NULL DEFAULT FALSE,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(service_id, carrier_company_id),
    UNIQUE(carrier_company_id, service_code),

    CHECK(delivery_speed IS NULL OR delivery_speed IN (
        'SAME_DAY',
        'NEXT_DAY',
        'EXPRESS',
        'STANDARD',
        'ECONOMY',
        'FREIGHT'
    ))
);

CREATE INDEX courier_services_company_idx
ON logistics.courier_services(carrier_company_id, is_active);


-- =========================================================
-- 3. COURIER INTEGRATIONS
-- Stores per-market integration configuration.
-- Never store API passwords or secret keys directly here.
-- credentials_secret_ref points to a secure secret manager.
-- =========================================================

CREATE TABLE logistics.courier_integrations (
    integration_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    market_id UUID NOT NULL
        REFERENCES core.markets(market_id),

    carrier_company_id UUID NOT NULL
        REFERENCES logistics.courier_companies(carrier_company_id),

    integration_mode VARCHAR(25) NOT NULL DEFAULT 'API',

    integration_status VARCHAR(30) NOT NULL DEFAULT 'NOT_CONFIGURED',

    account_reference VARCHAR(180),

    credentials_secret_ref TEXT,

    configuration JSONB NOT NULL DEFAULT '{}'::jsonb,

    last_successful_connection_at TIMESTAMPTZ,
    last_error TEXT,

    is_active BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(market_id, carrier_company_id),
    UNIQUE(integration_id, market_id, carrier_company_id),

    CHECK(integration_mode IN (
        'API',
        'MANUAL',
        'CONTRACT'
    )),

    CHECK(integration_status IN (
        'NOT_CONFIGURED',
        'PENDING',
        'CONNECTED',
        'FAILED',
        'SUSPENDED'
    ))
);

CREATE INDEX courier_integrations_market_idx
ON logistics.courier_integrations(market_id, is_active);


-- =========================================================
-- 4. MARKET COURIER SERVICES
-- Determines which courier services are enabled in a market.
-- A service must have an integration configured for that market.
-- =========================================================

CREATE TABLE logistics.market_courier_services (
    market_service_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    market_id UUID NOT NULL,
    carrier_company_id UUID NOT NULL,
    service_id UUID NOT NULL,

    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,

    priority_order INTEGER NOT NULL DEFAULT 0,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(market_id, carrier_company_id, service_id),
    UNIQUE(market_id, carrier_company_id, service_id, market_service_id),

    FOREIGN KEY(market_id, carrier_company_id)
        REFERENCES logistics.courier_integrations(
            market_id, carrier_company_id
        ),

    FOREIGN KEY(service_id, carrier_company_id)
        REFERENCES logistics.courier_services(
            service_id, carrier_company_id
        ),

    CHECK(priority_order >= 0)
);

CREATE INDEX market_courier_services_idx
ON logistics.market_courier_services(market_id, is_enabled);


-- =========================================================
-- 5. SHIPPING RATE QUOTES
-- Stores courier quotations before shipment booking.
-- Quotations can expire and should not be reused indefinitely.
-- =========================================================

CREATE TABLE logistics.shipping_rate_quotes (
    rate_quote_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    vendor_order_id UUID NOT NULL,
    market_id UUID NOT NULL,

    carrier_company_id UUID NOT NULL,
    service_id UUID NOT NULL,

    currency_code CHAR(3) NOT NULL,

    quote_source VARCHAR(20) NOT NULL DEFAULT 'API',

    quote_status VARCHAR(20) NOT NULL DEFAULT 'AVAILABLE',

    base_charge_minor BIGINT NOT NULL DEFAULT 0,
    fuel_surcharge_minor BIGINT NOT NULL DEFAULT 0,
    remote_area_surcharge_minor BIGINT NOT NULL DEFAULT 0,
    insurance_charge_minor BIGINT NOT NULL DEFAULT 0,
    tax_minor BIGINT NOT NULL DEFAULT 0,
    other_charges_minor BIGINT NOT NULL DEFAULT 0,

    total_charge_minor BIGINT NOT NULL,

    estimated_delivery_at TIMESTAMPTZ,

    chargeable_weight_grams NUMERIC(14,3),

    volumetric_divisor NUMERIC(12,3),

    provider_quote_reference VARCHAR(180),

    quote_details JSONB NOT NULL DEFAULT '{}'::jsonb,

    quoted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(rate_quote_id, vendor_order_id, market_id),

    FOREIGN KEY(vendor_order_id, market_id)
        REFERENCES sales.vendor_orders(vendor_order_id, market_id),

    FOREIGN KEY(market_id, carrier_company_id, service_id)
        REFERENCES logistics.market_courier_services(
            market_id, carrier_company_id, service_id
        ),

    FOREIGN KEY(market_id, currency_code)
        REFERENCES core.markets(market_id, settlement_currency),

    CHECK(quote_source IN ('API', 'MANUAL', 'CONTRACT')),

    CHECK(quote_status IN (
        'AVAILABLE',
        'SELECTED',
        'EXPIRED',
        'REJECTED',
        'BOOKED'
    )),

    CHECK(base_charge_minor >= 0),
    CHECK(fuel_surcharge_minor >= 0),
    CHECK(remote_area_surcharge_minor >= 0),
    CHECK(insurance_charge_minor >= 0),
    CHECK(tax_minor >= 0),
    CHECK(other_charges_minor >= 0),
    CHECK(total_charge_minor >= 0),

    CHECK(
        total_charge_minor =
            base_charge_minor
            + fuel_surcharge_minor
            + remote_area_surcharge_minor
            + insurance_charge_minor
            + tax_minor
            + other_charges_minor
    ),

    CHECK(chargeable_weight_grams IS NULL OR chargeable_weight_grams > 0),
    CHECK(volumetric_divisor IS NULL OR volumetric_divisor > 0),
    CHECK(expires_at IS NULL OR expires_at > quoted_at)
);

CREATE INDEX shipping_rate_quotes_order_idx
ON logistics.shipping_rate_quotes(vendor_order_id, quoted_at DESC);

CREATE INDEX shipping_rate_quotes_carrier_idx
ON logistics.shipping_rate_quotes(
    market_id, carrier_company_id, service_id
);


-- =========================================================
-- 6. SHIPMENTS
-- One vendor order may have multiple shipments.
-- Supports third-party couriers and internal delivery.
-- =========================================================

CREATE TABLE logistics.shipments (
    shipment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    vendor_order_id UUID NOT NULL,
    order_id UUID NOT NULL,
    market_id UUID NOT NULL,
    vendor_id UUID NOT NULL,

    shipment_number VARCHAR(80) NOT NULL,

    delivery_method VARCHAR(30) NOT NULL,

    carrier_company_id UUID,
    service_id UUID,

    rate_quote_id UUID,

    currency_code CHAR(3) NOT NULL,

    carrier_tracking_number VARCHAR(180),
    external_shipment_reference VARCHAR(180),

    shipment_status VARCHAR(35) NOT NULL DEFAULT 'PENDING',

    carrier_cost_minor BIGINT NOT NULL DEFAULT 0,
    customer_delivery_fee_minor BIGINT NOT NULL DEFAULT 0,

    dispatch_notes TEXT,

    booked_at TIMESTAMPTZ,
    picked_up_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(shipment_id, vendor_order_id, order_id, market_id, vendor_id),
    UNIQUE(shipment_id, order_id, market_id, vendor_id),
    UNIQUE(market_id, shipment_number),
    UNIQUE(shipment_id, currency_code),

    FOREIGN KEY(vendor_order_id, order_id, market_id, vendor_id)
        REFERENCES sales.vendor_orders(
            vendor_order_id, order_id, market_id, vendor_id
        ),

    FOREIGN KEY(rate_quote_id, vendor_order_id, market_id)
        REFERENCES logistics.shipping_rate_quotes(
            rate_quote_id, vendor_order_id, market_id
        ),

    FOREIGN KEY(market_id, carrier_company_id, service_id)
        REFERENCES logistics.market_courier_services(
            market_id, carrier_company_id, service_id
        ),

    FOREIGN KEY(market_id, currency_code)
        REFERENCES core.markets(market_id, settlement_currency),

    CHECK(delivery_method IN (
        'THIRD_PARTY_COURIER',
        'INTERNAL_RIDER',
        'CUSTOMER_PICKUP'
    )),

    CHECK(
        (
            delivery_method = 'THIRD_PARTY_COURIER'
            AND carrier_company_id IS NOT NULL
            AND service_id IS NOT NULL
        )
        OR
        (
            delivery_method IN ('INTERNAL_RIDER', 'CUSTOMER_PICKUP')
            AND carrier_company_id IS NULL
            AND service_id IS NULL
        )
    ),

    CHECK(shipment_status IN (
        'PENDING',
        'QUOTED',
        'BOOKED',
        'AWAITING_PICKUP',
        'PICKED_UP',
        'IN_TRANSIT',
        'OUT_FOR_DELIVERY',
        'DELIVERED',
        'DELIVERY_FAILED',
        'RETURN_IN_TRANSIT',
        'RETURNED',
        'CANCELLED'
    )),

    CHECK(carrier_cost_minor >= 0),
    CHECK(customer_delivery_fee_minor >= 0)
);

CREATE INDEX shipments_vendor_order_idx
ON logistics.shipments(vendor_order_id, created_at DESC);

CREATE INDEX shipments_status_idx
ON logistics.shipments(market_id, shipment_status, created_at DESC);

CREATE UNIQUE INDEX shipments_carrier_tracking_unique_idx
ON logistics.shipments(carrier_company_id, carrier_tracking_number)
WHERE carrier_tracking_number IS NOT NULL;


-- =========================================================
-- 7. SHIPMENT PACKAGES
-- Actual packed weight and dimensions are recorded here.
--
-- Weight: grams
-- Dimensions: millimetres
--
-- Chargeable weight is a snapshot after applying the
-- courier's volumetric divisor and rounding rules.
-- =========================================================

CREATE TABLE logistics.shipment_packages (
    package_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    shipment_id UUID NOT NULL,

    package_number VARCHAR(80) NOT NULL,

    package_type VARCHAR(40) NOT NULL DEFAULT 'BOX',

    actual_weight_grams NUMERIC(14,3) NOT NULL,

    length_mm NUMERIC(14,2),
    width_mm NUMERIC(14,2),
    height_mm NUMERIC(14,2),

    volumetric_divisor NUMERIC(12,3),
    volumetric_weight_grams NUMERIC(14,3),

    chargeable_weight_grams NUMERIC(14,3),

    declared_value_minor BIGINT NOT NULL DEFAULT 0,

    currency_code CHAR(3) NOT NULL,

    packaging_notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(package_id, shipment_id),
    UNIQUE(shipment_id, package_number),

    FOREIGN KEY(shipment_id)
        REFERENCES logistics.shipments(shipment_id)
        ON DELETE CASCADE,
    
    FOREIGN KEY(shipment_id, currency_code)
    REFERENCES logistics.shipments(shipment_id, currency_code)
    ON DELETE CASCADE,

    CHECK(package_type IN (
        'BOX',
        'ENVELOPE',
        'PALLET',
        'CRATE',
        'BAG',
        'OTHER'
    )),

    CHECK(actual_weight_grams > 0),

    CHECK(length_mm IS NULL OR length_mm > 0),
    CHECK(width_mm IS NULL OR width_mm > 0),
    CHECK(height_mm IS NULL OR height_mm > 0),

    CHECK(volumetric_divisor IS NULL OR volumetric_divisor > 0),
    CHECK(volumetric_weight_grams IS NULL OR volumetric_weight_grams > 0),
    CHECK(chargeable_weight_grams IS NULL OR chargeable_weight_grams > 0),

    CHECK(declared_value_minor >= 0)
);

CREATE INDEX shipment_packages_shipment_idx
ON logistics.shipment_packages(shipment_id);


-- =========================================================
-- 8. SHIPMENT ITEMS
-- Records which products and quantities are inside packages.
-- Supports splitting an order item across multiple packages.
-- =========================================================

CREATE TABLE logistics.shipment_items (
    shipment_item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    shipment_id UUID NOT NULL,
    package_id UUID NOT NULL,

    order_id UUID NOT NULL,
    order_item_id UUID NOT NULL,

    market_id UUID NOT NULL,
    vendor_id UUID NOT NULL,

    quantity_shipped NUMERIC(18,3) NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    FOREIGN KEY(shipment_id, order_id, market_id, vendor_id)
        REFERENCES logistics.shipments(
            shipment_id, order_id, market_id, vendor_id
        )
        ON DELETE CASCADE,

    FOREIGN KEY(package_id, shipment_id)
        REFERENCES logistics.shipment_packages(package_id, shipment_id)
        ON DELETE CASCADE,

    FOREIGN KEY(order_item_id, order_id, market_id, vendor_id)
        REFERENCES sales.order_items(
            order_item_id, order_id, market_id, vendor_id
        ),

    CHECK(quantity_shipped > 0)
);

CREATE INDEX shipment_items_shipment_idx
ON logistics.shipment_items(shipment_id);

CREATE INDEX shipment_items_package_idx
ON logistics.shipment_items(package_id);

CREATE INDEX shipment_items_order_item_idx
ON logistics.shipment_items(order_item_id);


-- =========================================================
-- 9. SHIPMENT TRACKING EVENTS
-- Stores tracking updates from external couriers or our
-- own delivery system.
-- =========================================================

CREATE TABLE logistics.shipment_tracking_events (
    tracking_event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    shipment_id UUID NOT NULL
        REFERENCES logistics.shipments(shipment_id)
        ON DELETE CASCADE,

    event_code VARCHAR(100),
    event_status VARCHAR(35) NOT NULL,

    event_description TEXT,

    event_source VARCHAR(25) NOT NULL DEFAULT 'SYSTEM',

    event_location VARCHAR(255),

    location GEOGRAPHY(POINT, 4326),

    provider_event_reference VARCHAR(180),

    event_time TIMESTAMPTZ NOT NULL,

    event_payload JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CHECK(event_source IN (
        'COURIER_API',
        'MANUAL',
        'SYSTEM',
        'INTERNAL_RIDER'
    )),

    CHECK(event_status IN (
        'PENDING',
        'BOOKED',
        'AWAITING_PICKUP',
        'PICKED_UP',
        'IN_TRANSIT',
        'CUSTOMS_CLEARANCE',
        'OUT_FOR_DELIVERY',
        'DELIVERED',
        'DELIVERY_FAILED',
        'RETURN_IN_TRANSIT',
        'RETURNED',
        'CANCELLED',
        'EXCEPTION'
    ))
);

CREATE INDEX shipment_tracking_history_idx
ON logistics.shipment_tracking_events(shipment_id, event_time DESC);

CREATE INDEX shipment_tracking_status_idx
ON logistics.shipment_tracking_events(event_status, event_time DESC);


-- =========================================================
-- 10. SHIPMENT LABELS
-- Store label files in private object storage.
-- PostgreSQL stores only the storage key and metadata.
-- =========================================================

CREATE TABLE logistics.shipment_labels (
    label_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    shipment_id UUID NOT NULL,
    package_id UUID,

    storage_key TEXT NOT NULL,

    label_format VARCHAR(20) NOT NULL,

    label_type VARCHAR(25) NOT NULL DEFAULT 'SHIPPING',

    carrier_label_reference VARCHAR(180),

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    FOREIGN KEY(shipment_id)
        REFERENCES logistics.shipments(shipment_id)
        ON DELETE CASCADE,

    FOREIGN KEY(package_id, shipment_id)
        REFERENCES logistics.shipment_packages(package_id, shipment_id),

    UNIQUE(storage_key),

    CHECK(label_format IN (
        'PDF',
        'PNG',
        'ZPL',
        'EPL',
        'OTHER'
    )),

    CHECK(label_type IN (
        'SHIPPING',
        'RETURN',
        'CUSTOMS',
        'OTHER'
    ))
);

CREATE INDEX shipment_labels_shipment_idx
ON logistics.shipment_labels(shipment_id, created_at DESC);


COMMIT;
