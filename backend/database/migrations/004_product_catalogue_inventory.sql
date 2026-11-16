
BEGIN;

CREATE SCHEMA IF NOT EXISTS catalog;
CREATE SCHEMA IF NOT EXISTS inventory;

-- =========================================================
-- 1. PRODUCT CATEGORIES
-- =========================================================

CREATE TABLE catalog.categories (
    category_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    market_id UUID NOT NULL REFERENCES core.markets(market_id),
    parent_category_id UUID,
    category_name VARCHAR(150) NOT NULL,
    category_slug VARCHAR(180) NOT NULL,
    description TEXT,
    image_key TEXT,
    display_order INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(category_id, market_id),
    UNIQUE(market_id, category_slug),

    FOREIGN KEY(parent_category_id, market_id)
        REFERENCES catalog.categories(category_id, market_id)
        ON DELETE RESTRICT,

    CHECK(parent_category_id IS NULL OR parent_category_id <> category_id)
);

CREATE INDEX categories_market_idx
ON catalog.categories(market_id, is_active);


-- =========================================================
-- 2. PRODUCTS
-- =========================================================

CREATE TABLE catalog.products (
    product_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    market_id UUID NOT NULL REFERENCES core.markets(market_id),
    category_id UUID,
    product_name VARCHAR(250) NOT NULL,
    product_slug VARCHAR(280) NOT NULL,
    brand_name VARCHAR(150),
    description TEXT,
    product_type VARCHAR(40) NOT NULL DEFAULT 'PHYSICAL',
    approval_status VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_by UUID REFERENCES identity.users(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(product_id, market_id),
    UNIQUE(market_id, product_slug),

    FOREIGN KEY(category_id, market_id)
        REFERENCES catalog.categories(category_id, market_id),

    CHECK(product_type IN ('PHYSICAL', 'DIGITAL', 'SERVICE')),
    CHECK(approval_status IN ('PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED'))
);

CREATE INDEX products_market_idx
ON catalog.products(market_id, is_active);

CREATE INDEX products_category_idx
ON catalog.products(category_id);

CREATE INDEX products_name_idx
ON catalog.products USING GIN (to_tsvector('simple', product_name));


-- =========================================================
-- 3. PRODUCT IMAGES
-- Multiple images per product; one active primary image.
-- Actual image files will be stored in object storage.
-- =========================================================

CREATE TABLE catalog.product_images (
    image_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL,
    market_id UUID NOT NULL,
    storage_key TEXT NOT NULL,
    original_filename VARCHAR(255),
    mime_type VARCHAR(100) NOT NULL,
    file_size_bytes BIGINT,
    image_width INTEGER,
    image_height INTEGER,
    alt_text VARCHAR(255),
    caption VARCHAR(255),
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    display_order INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    uploaded_by UUID REFERENCES identity.users(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    FOREIGN KEY(product_id, market_id)
        REFERENCES catalog.products(product_id, market_id)
        ON DELETE CASCADE,

    UNIQUE(market_id, storage_key),

    CHECK(file_size_bytes IS NULL OR file_size_bytes > 0),
    CHECK(image_width IS NULL OR image_width > 0),
    CHECK(image_height IS NULL OR image_height > 0)
);

CREATE INDEX product_images_product_idx
ON catalog.product_images(product_id, display_order);

CREATE UNIQUE INDEX product_images_one_primary_idx
ON catalog.product_images(product_id)
WHERE is_primary = TRUE AND is_active = TRUE;


-- =========================================================
-- 4. PRODUCT VARIANTS
-- Weight and dimensions describe the standard product variant.
-- Weight is in grams; dimensions are in millimetres.
-- =========================================================

CREATE TABLE catalog.product_variants (
    variant_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL,
    market_id UUID NOT NULL,
    variant_name VARCHAR(180) NOT NULL,
    attributes JSONB NOT NULL DEFAULT '{}'::jsonb,

    weight_grams NUMERIC(12,3),
    length_mm NUMERIC(12,2),
    width_mm NUMERIC(12,2),
    height_mm NUMERIC(12,2),

    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(variant_id, market_id),
    UNIQUE(variant_id, product_id, market_id),

    FOREIGN KEY(product_id, market_id)
        REFERENCES catalog.products(product_id, market_id)
        ON DELETE CASCADE,

    CHECK(weight_grams IS NULL OR weight_grams > 0),
    CHECK(length_mm IS NULL OR length_mm > 0),
    CHECK(width_mm IS NULL OR width_mm > 0),
    CHECK(height_mm IS NULL OR height_mm > 0)
);

CREATE INDEX product_variants_product_idx
ON catalog.product_variants(product_id);


-- =========================================================
-- 5. VENDOR PRODUCTS
-- A vendor's listing of a catalogue product.
-- =========================================================

CREATE TABLE catalog.vendor_products (
    vendor_product_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_id UUID NOT NULL,
    market_id UUID NOT NULL,
    product_id UUID NOT NULL,
    vendor_title VARCHAR(250),
    vendor_description TEXT,
    listing_status VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    approval_status VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_by UUID REFERENCES identity.users(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(vendor_product_id, market_id),
    UNIQUE(vendor_product_id, product_id, market_id),

    FOREIGN KEY(vendor_id, market_id)
        REFERENCES vendors.vendors(vendor_id, market_id),

    FOREIGN KEY(product_id, market_id)
        REFERENCES catalog.products(product_id, market_id),

    UNIQUE(vendor_id, product_id),

    CHECK(listing_status IN ('DRAFT', 'ACTIVE', 'PAUSED', 'DISCONTINUED')),
    CHECK(approval_status IN ('PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED'))
);

CREATE INDEX vendor_products_vendor_idx
ON catalog.vendor_products(vendor_id, is_active);

CREATE INDEX vendor_products_product_idx
ON catalog.vendor_products(product_id, is_active);


-- =========================================================
-- 6. VENDOR PRODUCT VARIANTS
-- Vendor-specific price, SKU and packaged shipping dimensions.
-- These fields support courier weight and volumetric pricing.
-- =========================================================

CREATE TABLE catalog.vendor_product_variants (
    vendor_product_variant_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_product_id UUID NOT NULL,
    product_id UUID NOT NULL,
    market_id UUID NOT NULL,
    variant_id UUID NOT NULL,
    vendor_sku VARCHAR(100) NOT NULL,

    selling_price_minor BIGINT NOT NULL,
    compare_at_price_minor BIGINT,
    currency_code CHAR(3) NOT NULL,

    shipping_weight_grams NUMERIC(12,3),
    shipping_length_mm NUMERIC(12,2),
    shipping_width_mm NUMERIC(12,2),
    shipping_height_mm NUMERIC(12,2),

    is_available BOOLEAN NOT NULL DEFAULT TRUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(vendor_product_variant_id, market_id),
    UNIQUE(vendor_product_variant_id, product_id, market_id),
    UNIQUE(vendor_product_id, variant_id),
    UNIQUE(vendor_product_id, vendor_sku),

    FOREIGN KEY(vendor_product_id, product_id, market_id)
        REFERENCES catalog.vendor_products(
            vendor_product_id, product_id, market_id
        ),

    FOREIGN KEY(variant_id, product_id, market_id)
        REFERENCES catalog.product_variants(
            variant_id, product_id, market_id
        ),

    CHECK(selling_price_minor >= 0),
    CHECK(compare_at_price_minor IS NULL OR compare_at_price_minor >= 0),

    CHECK(shipping_weight_grams IS NULL OR shipping_weight_grams > 0),
    CHECK(shipping_length_mm IS NULL OR shipping_length_mm > 0),
    CHECK(shipping_width_mm IS NULL OR shipping_width_mm > 0),
    CHECK(shipping_height_mm IS NULL OR shipping_height_mm > 0)
);

CREATE INDEX vendor_variant_price_idx
ON catalog.vendor_product_variants(
    market_id, currency_code, selling_price_minor
);


-- =========================================================
-- 7. VENDOR PRODUCT IMAGES
-- Allows vendors to upload their own listing images.
-- =========================================================

CREATE TABLE catalog.vendor_product_images (
    vendor_image_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_product_id UUID NOT NULL,
    market_id UUID NOT NULL,
    storage_key TEXT NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    original_filename VARCHAR(255),
    file_size_bytes BIGINT,
    alt_text VARCHAR(255),
    caption VARCHAR(255),
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    display_order INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    uploaded_by UUID REFERENCES identity.users(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    FOREIGN KEY(vendor_product_id, market_id)
        REFERENCES catalog.vendor_products(vendor_product_id, market_id)
        ON DELETE CASCADE,

    UNIQUE(market_id, storage_key),

    CHECK(file_size_bytes IS NULL OR file_size_bytes > 0)
);

CREATE INDEX vendor_product_images_idx
ON catalog.vendor_product_images(vendor_product_id, display_order);

CREATE UNIQUE INDEX vendor_product_images_primary_idx
ON catalog.vendor_product_images(vendor_product_id)
WHERE is_primary = TRUE AND is_active = TRUE;


-- =========================================================
-- 8. PRODUCT BARCODES
-- Supports multiple barcode types for a vendor variant.
-- =========================================================

CREATE TABLE catalog.product_barcodes (
    barcode_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_product_variant_id UUID NOT NULL,
    market_id UUID NOT NULL,
    barcode_value VARCHAR(150) NOT NULL,
    barcode_type VARCHAR(30) NOT NULL DEFAULT 'EAN13',
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    FOREIGN KEY(vendor_product_variant_id, market_id)
        REFERENCES catalog.vendor_product_variants(
            vendor_product_variant_id, market_id
        )
        ON DELETE CASCADE,

    CHECK(barcode_type IN (
        'EAN8', 'EAN13', 'UPC_A', 'UPC_E',
        'CODE128', 'CODE39', 'QR', 'OTHER'
    ))
);

CREATE UNIQUE INDEX product_barcodes_market_value_idx
ON catalog.product_barcodes(market_id, barcode_value)
WHERE is_active = TRUE;

CREATE INDEX product_barcodes_variant_idx
ON catalog.product_barcodes(vendor_product_variant_id);


-- =========================================================
-- 9. BRANCH OWNERSHIP CONSTRAINT
-- Enables warehouses to reference a branch belonging to
-- the same vendor and market.
-- =========================================================

ALTER TABLE vendors.branches
ADD CONSTRAINT branches_branch_vendor_market_uq
UNIQUE(branch_id, vendor_id, market_id);


-- =========================================================
-- 10. WAREHOUSES
-- A vendor may have multiple warehouses.
-- A warehouse may optionally belong to a branch.
-- =========================================================

CREATE TABLE inventory.warehouses (
    warehouse_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_id UUID NOT NULL,
    market_id UUID NOT NULL,
    branch_id UUID,
    warehouse_name VARCHAR(180) NOT NULL,
    warehouse_code VARCHAR(80) NOT NULL,
    address TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(warehouse_id, market_id),
    UNIQUE(vendor_id, warehouse_code),

    FOREIGN KEY(vendor_id, market_id)
        REFERENCES vendors.vendors(vendor_id, market_id),

    FOREIGN KEY(branch_id, vendor_id, market_id)
        REFERENCES vendors.branches(branch_id, vendor_id, market_id)
        ON DELETE RESTRICT
);

CREATE INDEX warehouses_vendor_idx
ON inventory.warehouses(vendor_id, is_active);


-- =========================================================
-- 11. STOCK LEVELS
-- =========================================================

CREATE TABLE inventory.stock_levels (
    stock_level_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    warehouse_id UUID NOT NULL,
    vendor_product_variant_id UUID NOT NULL,
    market_id UUID NOT NULL,
    quantity_on_hand NUMERIC(18,3) NOT NULL DEFAULT 0,
    quantity_reserved NUMERIC(18,3) NOT NULL DEFAULT 0,
    reorder_level NUMERIC(18,3) NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(warehouse_id, vendor_product_variant_id),

    FOREIGN KEY(warehouse_id, market_id)
        REFERENCES inventory.warehouses(warehouse_id, market_id),

    FOREIGN KEY(vendor_product_variant_id, market_id)
        REFERENCES catalog.vendor_product_variants(
            vendor_product_variant_id, market_id
        ),

    CHECK(quantity_on_hand >= 0),
    CHECK(quantity_reserved >= 0),
    CHECK(quantity_reserved <= quantity_on_hand),
    CHECK(reorder_level >= 0)
);

CREATE INDEX stock_levels_low_stock_idx
ON inventory.stock_levels(warehouse_id)
WHERE quantity_on_hand <= reorder_level;


-- =========================================================
-- 12. STOCK BATCHES
-- Supports expiry dates and batch-level stock tracking.
-- =========================================================

CREATE TABLE inventory.stock_batches (
    batch_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stock_level_id UUID NOT NULL
        REFERENCES inventory.stock_levels(stock_level_id),
    batch_number VARCHAR(120),
    manufacture_date DATE,
    expiry_date DATE,
    quantity_received NUMERIC(18,3) NOT NULL,
    quantity_remaining NUMERIC(18,3) NOT NULL,
    unit_cost_minor BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CHECK(quantity_received > 0),
    CHECK(quantity_remaining >= 0),
    CHECK(quantity_remaining <= quantity_received),
    CHECK(unit_cost_minor IS NULL OR unit_cost_minor >= 0),
    CHECK(
        manufacture_date IS NULL
        OR expiry_date IS NULL
        OR expiry_date >= manufacture_date
    )
);

CREATE INDEX stock_batches_expiry_idx
ON inventory.stock_batches(expiry_date)
WHERE quantity_remaining > 0;

CREATE INDEX stock_batches_stock_idx
ON inventory.stock_batches(stock_level_id);


-- =========================================================
-- 13. STOCK MOVEMENTS
-- Records all stock additions, deductions and adjustments.
-- =========================================================

CREATE TABLE inventory.stock_movements (
    movement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    market_id UUID NOT NULL,
    warehouse_id UUID NOT NULL,
    vendor_product_variant_id UUID NOT NULL,
    movement_type VARCHAR(35) NOT NULL,
    quantity NUMERIC(18,3) NOT NULL,
    reference_type VARCHAR(50),
    reference_id UUID,
    notes TEXT,
    performed_by UUID REFERENCES identity.users(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    FOREIGN KEY(warehouse_id, market_id)
        REFERENCES inventory.warehouses(warehouse_id, market_id),

    FOREIGN KEY(vendor_product_variant_id, market_id)
        REFERENCES catalog.vendor_product_variants(
            vendor_product_variant_id, market_id
        ),

    CHECK(quantity > 0),

    CHECK(movement_type IN (
        'OPENING_STOCK',
        'PURCHASE_RECEIVED',
        'SALE',
        'SALE_RETURN',
        'PURCHASE_RETURN',
        'TRANSFER_IN',
        'TRANSFER_OUT',
        'ADJUSTMENT_IN',
        'ADJUSTMENT_OUT',
        'DAMAGED',
        'EXPIRED',
        'RESERVATION',
        'RESERVATION_RELEASE'
    ))
);

CREATE INDEX stock_movements_warehouse_idx
ON inventory.stock_movements(warehouse_id, created_at DESC);

CREATE INDEX stock_movements_variant_idx
ON inventory.stock_movements(
    vendor_product_variant_id, created_at DESC
);


-- =========================================================
-- 14. STOCK ALERTS
-- =========================================================

CREATE TABLE inventory.stock_alerts (
    alert_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stock_level_id UUID NOT NULL
        REFERENCES inventory.stock_levels(stock_level_id),
    alert_type VARCHAR(30) NOT NULL,
    alert_message TEXT,
    is_resolved BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ,

    CHECK(alert_type IN (
        'LOW_STOCK',
        'OUT_OF_STOCK',
        'EXPIRING_SOON',
        'EXPIRED'
    ))
);

CREATE INDEX stock_alerts_unresolved_idx
ON inventory.stock_alerts(stock_level_id, created_at DESC)
WHERE is_resolved = FALSE;


-- =========================================================
-- FINISH MIGRATION
-- =========================================================

COMMIT;
