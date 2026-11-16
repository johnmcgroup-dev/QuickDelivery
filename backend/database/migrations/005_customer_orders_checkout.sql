
BEGIN;

CREATE SCHEMA IF NOT EXISTS sales;

-- =========================================================
-- 1. ENFORCE MARKET SETTLEMENT CURRENCY
-- Every order must use its market's configured currency.
-- =========================================================

ALTER TABLE core.markets
ADD CONSTRAINT markets_market_currency_uq
UNIQUE (market_id, settlement_currency);


-- =========================================================
-- 2. CUSTOMER DELIVERY ADDRESSES
-- Customers can save multiple addresses.
-- =========================================================

CREATE TABLE sales.customer_addresses (
    address_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL
        REFERENCES identity.users(user_id),

    market_id UUID NOT NULL
        REFERENCES core.markets(market_id),

    address_label VARCHAR(100) NOT NULL,
    recipient_name VARCHAR(200) NOT NULL,
    recipient_phone VARCHAR(30) NOT NULL,

    country_code CHAR(2) NOT NULL,
    state_region VARCHAR(150),
    city VARCHAR(150) NOT NULL,
    postal_code VARCHAR(30),

    address_line_1 VARCHAR(255) NOT NULL,
    address_line_2 VARCHAR(255),
    landmark VARCHAR(255),

    location GEOGRAPHY(POINT, 4326),

    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(address_id, customer_id, market_id)
);

CREATE INDEX customer_addresses_customer_idx
ON sales.customer_addresses(customer_id, market_id);

CREATE UNIQUE INDEX customer_addresses_default_idx
ON sales.customer_addresses(customer_id, market_id)
WHERE is_default = TRUE AND is_active = TRUE;


-- =========================================================
-- 3. SHOPPING CARTS
-- One active cart per customer per market.
-- =========================================================

CREATE TABLE sales.carts (
    cart_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    customer_id UUID NOT NULL
        REFERENCES identity.users(user_id),

    market_id UUID NOT NULL
        REFERENCES core.markets(market_id),

    cart_status VARCHAR(25) NOT NULL DEFAULT 'ACTIVE',

    currency_code CHAR(3) NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,

    UNIQUE(cart_id, market_id),

    FOREIGN KEY(market_id, currency_code)
        REFERENCES core.markets(market_id, settlement_currency),

    CHECK(cart_status IN (
        'ACTIVE',
        'CHECKED_OUT',
        'ABANDONED',
        'EXPIRED'
    ))
);

CREATE UNIQUE INDEX carts_one_active_per_customer_idx
ON sales.carts(customer_id, market_id)
WHERE cart_status = 'ACTIVE';

CREATE INDEX carts_customer_idx
ON sales.carts(customer_id, created_at DESC);


-- =========================================================
-- 4. SHOPPING CART ITEMS
-- Cart items reference the vendor's actual product variant.
-- Prices are confirmed again during checkout.
-- =========================================================

CREATE TABLE sales.cart_items (
    cart_item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    cart_id UUID NOT NULL,
    market_id UUID NOT NULL,

    vendor_product_variant_id UUID NOT NULL,

    quantity NUMERIC(18,3) NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    FOREIGN KEY(cart_id, market_id)
        REFERENCES sales.carts(cart_id, market_id)
        ON DELETE CASCADE,

    FOREIGN KEY(vendor_product_variant_id, market_id)
        REFERENCES catalog.vendor_product_variants(
            vendor_product_variant_id, market_id
        ),

    UNIQUE(cart_id, vendor_product_variant_id),

    CHECK(quantity > 0)
);

CREATE INDEX cart_items_cart_idx
ON sales.cart_items(cart_id);


-- =========================================================
-- 5. CUSTOMER ORDERS
-- One main order represents one customer checkout.
-- Address information is snapshotted to preserve history.
-- =========================================================

CREATE TABLE sales.orders (
    order_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    market_id UUID NOT NULL,
    customer_id UUID NOT NULL
        REFERENCES identity.users(user_id),

    customer_address_id UUID,

    order_number VARCHAR(60) NOT NULL,

    currency_code CHAR(3) NOT NULL,

    order_status VARCHAR(30) NOT NULL DEFAULT 'PENDING',

    payment_status VARCHAR(30) NOT NULL DEFAULT 'UNPAID',

    delivery_status VARCHAR(30) NOT NULL DEFAULT 'PENDING',

    -- Delivery address snapshot
    recipient_name VARCHAR(200) NOT NULL,
    recipient_phone VARCHAR(30) NOT NULL,
    delivery_country_code CHAR(2) NOT NULL,
    delivery_state_region VARCHAR(150),
    delivery_city VARCHAR(150) NOT NULL,
    delivery_postal_code VARCHAR(30),
    delivery_address_line_1 VARCHAR(255) NOT NULL,
    delivery_address_line_2 VARCHAR(255),
    delivery_landmark VARCHAR(255),
    delivery_location GEOGRAPHY(POINT, 4326),

    -- Financial snapshots, stored in minor currency units
    subtotal_minor BIGINT NOT NULL DEFAULT 0,
    discount_minor BIGINT NOT NULL DEFAULT 0,
    tax_minor BIGINT NOT NULL DEFAULT 0,
    delivery_fee_minor BIGINT NOT NULL DEFAULT 0,
    total_minor BIGINT NOT NULL DEFAULT 0,

    customer_notes TEXT,

    idempotency_key VARCHAR(150),

    placed_at TIMESTAMPTZ,
    confirmed_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(order_id, market_id),
    UNIQUE(order_id, market_id, customer_id),
    UNIQUE(market_id, order_number),

    FOREIGN KEY(market_id, currency_code)
        REFERENCES core.markets(market_id, settlement_currency),

    FOREIGN KEY(customer_address_id, customer_id, market_id)
        REFERENCES sales.customer_addresses(
            address_id, customer_id, market_id
        ),

    CHECK(order_status IN (
        'PENDING',
        'CONFIRMED',
        'PROCESSING',
        'PARTIALLY_FULFILLED',
        'FULFILLED',
        'COMPLETED',
        'CANCELLED',
        'REJECTED'
    )),

    CHECK(payment_status IN (
        'UNPAID',
        'PENDING',
        'PAID',
        'PARTIALLY_PAID',
        'FAILED',
        'REFUNDED',
        'PARTIALLY_REFUNDED'
    )),

    CHECK(delivery_status IN (
        'PENDING',
        'AWAITING_DISPATCH',
        'PARTIALLY_DISPATCHED',
        'DISPATCHED',
        'IN_TRANSIT',
        'PARTIALLY_DELIVERED',
        'DELIVERED',
        'FAILED',
        'RETURNED'
    )),

    CHECK(subtotal_minor >= 0),
    CHECK(discount_minor >= 0),
    CHECK(tax_minor >= 0),
    CHECK(delivery_fee_minor >= 0),
    CHECK(total_minor >= 0),

    CHECK(total_minor =
        subtotal_minor - discount_minor
        + tax_minor + delivery_fee_minor
    )
);

CREATE INDEX orders_customer_idx
ON sales.orders(customer_id, created_at DESC);

CREATE INDEX orders_market_status_idx
ON sales.orders(market_id, order_status, created_at DESC);

CREATE INDEX orders_payment_status_idx
ON sales.orders(payment_status, created_at DESC);

CREATE UNIQUE INDEX orders_idempotency_idx
ON sales.orders(market_id, customer_id, idempotency_key)
WHERE idempotency_key IS NOT NULL;


-- =========================================================
-- 6. ORDER ITEMS
-- Product and pricing information is snapshotted at checkout.
-- Later catalogue changes must not alter historical orders.
-- =========================================================

CREATE TABLE sales.order_items (
    order_item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    order_id UUID NOT NULL,
    market_id UUID NOT NULL,
    customer_id UUID NOT NULL,

    vendor_id UUID NOT NULL,
    vendor_product_id UUID NOT NULL,

    product_id UUID NOT NULL,
    variant_id UUID NOT NULL,
    vendor_product_variant_id UUID NOT NULL,

    product_name_snapshot VARCHAR(250) NOT NULL,
    variant_name_snapshot VARCHAR(180) NOT NULL,
    vendor_name_snapshot VARCHAR(250) NOT NULL,
    sku_snapshot VARCHAR(100) NOT NULL,

    quantity NUMERIC(18,3) NOT NULL,

    currency_code CHAR(3) NOT NULL,

    unit_price_minor BIGINT NOT NULL,
    line_subtotal_minor BIGINT NOT NULL DEFAULT 0,
    discount_minor BIGINT NOT NULL DEFAULT 0,
    tax_minor BIGINT NOT NULL DEFAULT 0,
    line_total_minor BIGINT NOT NULL DEFAULT 0,

    -- Product and shipping measurements at checkout
    weight_grams NUMERIC(12,3),
    shipping_weight_grams NUMERIC(12,3),

    shipping_length_mm NUMERIC(12,2),
    shipping_width_mm NUMERIC(12,2),
    shipping_height_mm NUMERIC(12,2),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(order_item_id, order_id, market_id, vendor_id),
    UNIQUE(vendor_product_variant_id, order_id),

    FOREIGN KEY(order_id, market_id, customer_id)
        REFERENCES sales.orders(order_id, market_id, customer_id),

    FOREIGN KEY(vendor_id, market_id)
        REFERENCES vendors.vendors(vendor_id, market_id),

    FOREIGN KEY(vendor_product_id, product_id, market_id)
        REFERENCES catalog.vendor_products(
            vendor_product_id, product_id, market_id
        ),

    FOREIGN KEY(variant_id, product_id, market_id)
        REFERENCES catalog.product_variants(
            variant_id, product_id, market_id
        ),

    FOREIGN KEY(vendor_product_variant_id, product_id, market_id)
        REFERENCES catalog.vendor_product_variants(
            vendor_product_variant_id, product_id, market_id
        ),

    FOREIGN KEY(market_id, currency_code)
        REFERENCES core.markets(market_id, settlement_currency),

    CHECK(quantity > 0),
    CHECK(unit_price_minor >= 0),
    CHECK(line_subtotal_minor >= 0),
    CHECK(discount_minor >= 0),
    CHECK(tax_minor >= 0),
    CHECK(line_total_minor >= 0),

    CHECK(line_total_minor =
        line_subtotal_minor - discount_minor + tax_minor
    ),

    CHECK(weight_grams IS NULL OR weight_grams > 0),
    CHECK(shipping_weight_grams IS NULL OR shipping_weight_grams > 0),
    CHECK(shipping_length_mm IS NULL OR shipping_length_mm > 0),
    CHECK(shipping_width_mm IS NULL OR shipping_width_mm > 0),
    CHECK(shipping_height_mm IS NULL OR shipping_height_mm > 0)
);

CREATE INDEX order_items_order_idx
ON sales.order_items(order_id);

CREATE INDEX order_items_vendor_idx
ON sales.order_items(vendor_id, created_at DESC);

CREATE INDEX order_items_product_idx
ON sales.order_items(product_id);


-- =========================================================
-- 7. VENDOR ORDERS
-- Each vendor receives a separate fulfilment order.
-- One customer order can have several vendor orders.
-- =========================================================

CREATE TABLE sales.vendor_orders (
    vendor_order_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    order_id UUID NOT NULL,
    market_id UUID NOT NULL,
    vendor_id UUID NOT NULL,

    fulfillment_branch_id UUID,

    vendor_order_number VARCHAR(70) NOT NULL,

    vendor_order_status VARCHAR(30) NOT NULL DEFAULT 'PENDING',

    currency_code CHAR(3) NOT NULL,

    subtotal_minor BIGINT NOT NULL DEFAULT 0,
    discount_minor BIGINT NOT NULL DEFAULT 0,
    tax_minor BIGINT NOT NULL DEFAULT 0,
    delivery_fee_minor BIGINT NOT NULL DEFAULT 0,
    total_minor BIGINT NOT NULL DEFAULT 0,

    vendor_notes TEXT,

    accepted_at TIMESTAMPTZ,
    ready_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(vendor_order_id, order_id, market_id, vendor_id),
    UNIQUE(order_id, vendor_id),
    UNIQUE(market_id, vendor_order_number),

    FOREIGN KEY(order_id, market_id)
        REFERENCES sales.orders(order_id, market_id),

    FOREIGN KEY(vendor_id, market_id)
        REFERENCES vendors.vendors(vendor_id, market_id),

    FOREIGN KEY(fulfillment_branch_id, vendor_id, market_id)
        REFERENCES vendors.branches(branch_id, vendor_id, market_id),

    FOREIGN KEY(market_id, currency_code)
        REFERENCES core.markets(market_id, settlement_currency),

    CHECK(vendor_order_status IN (
        'PENDING',
        'ACCEPTED',
        'REJECTED',
        'PROCESSING',
        'READY_FOR_PICKUP',
        'DISPATCHED',
        'COMPLETED',
        'CANCELLED'
    )),

    CHECK(subtotal_minor >= 0),
    CHECK(discount_minor >= 0),
    CHECK(tax_minor >= 0),
    CHECK(delivery_fee_minor >= 0),
    CHECK(total_minor >= 0),

    CHECK(total_minor =
        subtotal_minor - discount_minor
        + tax_minor + delivery_fee_minor
    )
);

CREATE INDEX vendor_orders_vendor_idx
ON sales.vendor_orders(vendor_id, vendor_order_status, created_at DESC);

CREATE INDEX vendor_orders_order_idx
ON sales.vendor_orders(order_id);


-- =========================================================
-- 8. VENDOR ORDER ITEMS
-- Connects the customer's original order items to the
-- separate vendor fulfilment orders.
-- =========================================================

CREATE TABLE sales.vendor_order_items (
    vendor_order_item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    vendor_order_id UUID NOT NULL,
    order_id UUID NOT NULL,
    order_item_id UUID NOT NULL,

    market_id UUID NOT NULL,
    vendor_id UUID NOT NULL,

    quantity_to_fulfil NUMERIC(18,3) NOT NULL,
    quantity_fulfilled NUMERIC(18,3) NOT NULL DEFAULT 0,
    quantity_cancelled NUMERIC(18,3) NOT NULL DEFAULT 0,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    FOREIGN KEY(vendor_order_id, order_id, market_id, vendor_id)
        REFERENCES sales.vendor_orders(
            vendor_order_id, order_id, market_id, vendor_id
        )
        ON DELETE CASCADE,

    FOREIGN KEY(order_item_id, order_id, market_id, vendor_id)
        REFERENCES sales.order_items(
            order_item_id, order_id, market_id, vendor_id
        ),

    UNIQUE(order_item_id),

    CHECK(quantity_to_fulfil > 0),
    CHECK(quantity_fulfilled >= 0),
    CHECK(quantity_cancelled >= 0),

    CHECK(
        quantity_fulfilled + quantity_cancelled
        <= quantity_to_fulfil
    )
);

CREATE INDEX vendor_order_items_vendor_order_idx
ON sales.vendor_order_items(vendor_order_id);


-- =========================================================
-- 9. ORDER STATUS HISTORY
-- Records customer order status changes for auditing.
-- =========================================================

CREATE TABLE sales.order_status_history (
    history_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    order_id UUID NOT NULL,
    market_id UUID NOT NULL,

    previous_status VARCHAR(30),
    new_status VARCHAR(30) NOT NULL,

    change_reason TEXT,

    changed_by UUID REFERENCES identity.users(user_id),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    FOREIGN KEY(order_id, market_id)
        REFERENCES sales.orders(order_id, market_id)
        ON DELETE CASCADE,

    CHECK(new_status IN (
        'PENDING',
        'CONFIRMED',
        'PROCESSING',
        'PARTIALLY_FULFILLED',
        'FULFILLED',
        'COMPLETED',
        'CANCELLED',
        'REJECTED'
    )),

    CHECK(previous_status IS NULL OR previous_status IN (
        'PENDING',
        'CONFIRMED',
        'PROCESSING',
        'PARTIALLY_FULFILLED',
        'FULFILLED',
        'COMPLETED',
        'CANCELLED',
        'REJECTED'
    ))
);

CREATE INDEX order_status_history_order_idx
ON sales.order_status_history(order_id, created_at DESC);

-- Required composite unique constraint for logistics references
ALTER TABLE sales.vendor_orders
ADD CONSTRAINT vendor_orders_vendor_order_market_uq
UNIQUE (vendor_order_id, market_id);

COMMIT;
