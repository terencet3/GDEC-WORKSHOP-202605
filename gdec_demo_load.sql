-- =============================================================================
-- gdec_demo_load.sql
-- Synthetic Great Deals e-commerce dataset for the GDEC workshop.
-- Idempotent: safe to re-run. Drops and recreates the workshop database.
-- Designed for ACCOUNTADMIN role with WH_COCO_AI warehouse.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WH_COCO_AI;

CREATE DATABASE IF NOT EXISTS GDEC_DEMO;
USE DATABASE GDEC_DEMO;

CREATE SCHEMA IF NOT EXISTS COMMERCE;
USE SCHEMA COMMERCE;

-- ---------- Dimension tables ----------
CREATE OR REPLACE TABLE CUSTOMERS (
    customer_id      NUMBER       PRIMARY KEY,
    email            STRING,
    first_name       STRING,
    last_name        STRING,
    signup_date      DATE,
    region           STRING,
    loyalty_tier     STRING        -- BRONZE / SILVER / GOLD / PLATINUM
);

CREATE OR REPLACE TABLE PRODUCTS (
    product_id       NUMBER       PRIMARY KEY,
    sku              STRING,
    name             STRING,
    category         STRING,        -- APPAREL / ELECTRONICS / HOME / GROCERY / BEAUTY
    list_price       NUMBER(10,2),
    unit_cost        NUMBER(10,2),
    launch_date      DATE
);

-- ---------- Fact tables ----------
CREATE OR REPLACE TABLE ORDERS (
    order_id         NUMBER       PRIMARY KEY,
    customer_id      NUMBER,
    order_ts         TIMESTAMP_NTZ,
    status           STRING,        -- PLACED / PAID / SHIPPED / DELIVERED / RETURNED / CANCELLED
    total_amount     NUMBER(12,2),
    promo_code       STRING
);

CREATE OR REPLACE TABLE ORDER_ITEMS (
    order_item_id    NUMBER       PRIMARY KEY,
    order_id         NUMBER,
    product_id       NUMBER,
    quantity         NUMBER,
    unit_price       NUMBER(10,2)
);

CREATE OR REPLACE TABLE SHIPMENTS (
    shipment_id      NUMBER       PRIMARY KEY,
    order_id         NUMBER,
    carrier          STRING,        -- UPS / FEDEX / USPS / LBC / J&T
    promised_ts      TIMESTAMP_NTZ,
    shipped_ts       TIMESTAMP_NTZ,
    delivered_ts     TIMESTAMP_NTZ,
    sla_breach       BOOLEAN
);

CREATE OR REPLACE TABLE INVENTORY_SNAPSHOT (
    snapshot_date    DATE,
    product_id       NUMBER,
    on_hand          NUMBER,
    on_order         NUMBER
);

CREATE OR REPLACE TABLE WEB_EVENTS (
    event_id         NUMBER       PRIMARY KEY,
    customer_id      NUMBER,
    event_ts         TIMESTAMP_NTZ,
    event_type       STRING,        -- VIEW / ADD_TO_CART / REMOVE_FROM_CART / CHECKOUT / PURCHASE
    product_id       NUMBER,
    session_id       STRING
);

CREATE OR REPLACE TABLE PRODUCT_REVIEWS (
    review_id        NUMBER       PRIMARY KEY,
    product_id       NUMBER,
    customer_id      NUMBER,
    review_ts        TIMESTAMP_NTZ,
    rating           NUMBER,
    review_text      STRING
);

-- =============================================================================
-- Load synthetic data
-- =============================================================================

-- Customers (200)
INSERT INTO CUSTOMERS
SELECT
    SEQ4()                                                                    AS customer_id,
    'customer' || SEQ4() || '@greatdeals.example'                             AS email,
    DECODE(MOD(SEQ4(), 8), 0,'Maya',1,'Liam',2,'Aisha',3,'Noah',
                            4,'Chen',5,'Sofia',6,'Diego',7,'Priya')           AS first_name,
    DECODE(MOD(SEQ4(), 6), 0,'Reyes',1,'Park',2,'Khan',3,'Garcia',
                            4,'Smith',5,'Tanaka')                              AS last_name,
    DATEADD(day, -UNIFORM(1, 730, RANDOM()), CURRENT_DATE())                  AS signup_date,
    DECODE(MOD(SEQ4(), 5), 0,'NCR',1,'CALABARZON',2,'CENTRAL_LUZON',
                            3,'VISAYAS',4,'MINDANAO')                          AS region,
    DECODE(MOD(SEQ4(), 4), 0,'BRONZE',1,'SILVER',2,'GOLD',3,'PLATINUM')        AS loyalty_tier
FROM TABLE(GENERATOR(ROWCOUNT => 200));

-- Products (60)
INSERT INTO PRODUCTS
SELECT
    SEQ4()                                                                    AS product_id,
    'GD-' || LPAD(SEQ4()::STRING, 5, '0')                                     AS sku,
    DECODE(MOD(SEQ4(), 10),
        0,'Bamboo Hoodie', 1,'Wireless Earbuds Pro', 2,'Linen Bedsheets',
        3,'Cold Brew Concentrate', 4,'Vitamin C Serum', 5,'Running Shoes',
        6,'Smart Plug 2-pack', 7,'Memory Foam Pillow', 8,'Trail Mix 1kg',
        9,'Lipstick Set')                                                      AS name,
    DECODE(MOD(SEQ4(), 5), 0,'APPAREL',1,'ELECTRONICS',2,'HOME',
                            3,'GROCERY',4,'BEAUTY')                            AS category,
    ROUND(UNIFORM(199, 4999, RANDOM())/1.0, 2)                                AS list_price,
    ROUND(UNIFORM(80, 2400, RANDOM())/1.0, 2)                                 AS unit_cost,
    DATEADD(day, -UNIFORM(30, 900, RANDOM()), CURRENT_DATE())                 AS launch_date
FROM TABLE(GENERATOR(ROWCOUNT => 60));

-- Orders (5,000)
INSERT INTO ORDERS
SELECT
    SEQ4()                                                                    AS order_id,
    UNIFORM(0, 199, RANDOM())                                                 AS customer_id,
    DATEADD(second, -UNIFORM(1, 7776000, RANDOM()), CURRENT_TIMESTAMP())      AS order_ts,
    DECODE(MOD(SEQ4(), 10),
        0,'PLACED', 1,'PAID', 2,'PAID',
        3,'SHIPPED', 4,'SHIPPED', 5,'DELIVERED',
        6,'DELIVERED', 7,'DELIVERED', 8,'RETURNED', 9,'CANCELLED')             AS status,
    ROUND(UNIFORM(500, 25000, RANDOM())/1.0, 2)                               AS total_amount,
    DECODE(MOD(SEQ4(), 7), 0,'WELCOME10',1,'BIGSALE',2,NULL,
                            3,NULL,4,'LOYALTY15',5,NULL,6,'FLASH25')           AS promo_code
FROM TABLE(GENERATOR(ROWCOUNT => 5000));

-- Order items (avg 2 per order)
INSERT INTO ORDER_ITEMS
SELECT
    SEQ4()                                                                    AS order_item_id,
    UNIFORM(0, 4999, RANDOM())                                                AS order_id,
    UNIFORM(0, 59,   RANDOM())                                                AS product_id,
    UNIFORM(1, 4,    RANDOM())                                                AS quantity,
    ROUND(UNIFORM(150, 4500, RANDOM())/1.0, 2)                                AS unit_price
FROM TABLE(GENERATOR(ROWCOUNT => 10000));

-- Shipments (one per non-cancelled order, ~80%)
INSERT INTO SHIPMENTS
WITH shippable AS (
    SELECT order_id, order_ts FROM ORDERS WHERE status IN ('SHIPPED','DELIVERED','RETURNED')
)
SELECT
    ROW_NUMBER() OVER (ORDER BY order_id)                                     AS shipment_id,
    order_id                                                                  AS order_id,
    DECODE(MOD(order_id, 5), 0,'UPS',1,'FEDEX',2,'USPS',3,'LBC',4,'J&T')     AS carrier,
    DATEADD(day, 3, order_ts)                                                 AS promised_ts,
    DATEADD(hour, UNIFORM(2, 60, RANDOM()), order_ts)                         AS shipped_ts,
    DATEADD(day, UNIFORM(2, 7, RANDOM()), order_ts)                           AS delivered_ts,
    IFF(UNIFORM(0, 100, RANDOM()) < 18, TRUE, FALSE)                          AS sla_breach
FROM shippable;

-- Inventory snapshots (last 30 days, all products)
INSERT INTO INVENTORY_SNAPSHOT
SELECT
    DATEADD(day, -d.value, CURRENT_DATE())                                    AS snapshot_date,
    p.product_id                                                              AS product_id,
    UNIFORM(0, 500, RANDOM())                                                 AS on_hand,
    UNIFORM(0, 200, RANDOM())                                                 AS on_order
FROM PRODUCTS p,
     TABLE(FLATTEN(INPUT => ARRAY_GENERATE_RANGE(0, 30))) d;

-- Web events (20,000)
INSERT INTO WEB_EVENTS
SELECT
    SEQ4()                                                                    AS event_id,
    UNIFORM(0, 199, RANDOM())                                                 AS customer_id,
    DATEADD(second, -UNIFORM(1, 7776000, RANDOM()), CURRENT_TIMESTAMP())      AS event_ts,
    DECODE(MOD(SEQ4(), 10), 0,'VIEW',1,'VIEW',2,'VIEW',3,'VIEW',
                             4,'ADD_TO_CART',5,'ADD_TO_CART',
                             6,'REMOVE_FROM_CART',
                             7,'CHECKOUT',8,'CHECKOUT',9,'PURCHASE')           AS event_type,
    UNIFORM(0, 59, RANDOM())                                                  AS product_id,
    'sess_' || (SEQ4() / 5)::STRING                                           AS session_id
FROM TABLE(GENERATOR(ROWCOUNT => 20000));

-- Product reviews (2,000) — text varies by rating; useful for AI_SUMMARIZE / AI_CLASSIFY
INSERT INTO PRODUCT_REVIEWS
SELECT
    SEQ4()                                                                    AS review_id,
    UNIFORM(0, 59, RANDOM())                                                  AS product_id,
    UNIFORM(0, 199, RANDOM())                                                 AS customer_id,
    DATEADD(second, -UNIFORM(1, 7776000, RANDOM()), CURRENT_TIMESTAMP())      AS review_ts,
    UNIFORM(1, 5, RANDOM())                                                   AS rating,
    DECODE(MOD(SEQ4(), 6),
        0,'Loved it. Quality is great and shipping was fast.',
        1,'Did not match the description. Color was off and it arrived late.',
        2,'Solid value for the price. Would buy again.',
        3,'Stopped working after a week. Returning.',
        4,'Five stars. Customer support was responsive when I had questions.',
        5,'Average product. Nothing special but does the job.')                AS review_text
FROM TABLE(GENERATOR(ROWCOUNT => 2000));

-- =============================================================================
-- Sanity checks
-- =============================================================================
SELECT 'CUSTOMERS' AS table_name, COUNT(*) AS row_count FROM CUSTOMERS UNION ALL
SELECT 'PRODUCTS',         COUNT(*) FROM PRODUCTS         UNION ALL
SELECT 'ORDERS',           COUNT(*) FROM ORDERS           UNION ALL
SELECT 'ORDER_ITEMS',      COUNT(*) FROM ORDER_ITEMS      UNION ALL
SELECT 'SHIPMENTS',        COUNT(*) FROM SHIPMENTS        UNION ALL
SELECT 'INVENTORY_SNAPSHOT', COUNT(*) FROM INVENTORY_SNAPSHOT UNION ALL
SELECT 'WEB_EVENTS',       COUNT(*) FROM WEB_EVENTS       UNION ALL
SELECT 'PRODUCT_REVIEWS',  COUNT(*) FROM PRODUCT_REVIEWS;
