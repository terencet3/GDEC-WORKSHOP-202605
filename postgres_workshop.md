### Lab 4 — Snowflake Postgres: provisioning and transactional writes (35 min)

**Why it matters for Great Deals.** Your checkout flow needs sub-second writes and ACID guarantees that aren't a fit for a Snowflake warehouse. Snowflake Postgres gives you a managed, isolated Postgres instance behind your existing Snowflake auth and networking. In 35 minutes you'll provision one, attach a network policy, and run a transactional cart-and-checkout workload against it.

**What you'll learn.**
- How to provision a Snowflake Postgres instance from SQL.
- How to attach a network policy and connect via `psql`.
- How to model a small e-commerce transactional schema and run concurrent writes.

**Pre-check.**
- Your role has `CREATE POSTGRES INSTANCE` on the account (granted in pre-flight).
- The network policy `GDEC_PG_NETPOL` exists and includes your egress IP.
- `psql` is installed on your laptop (`brew install libpq && brew link --force libpq` on macOS, or `apt install postgresql-client` on Linux).

**Steps.**

1. In a Snowsight worksheet, create your instance:
   ```sql
   CREATE POSTGRES INSTANCE gdec_pg_<NN>
     COMPUTE_FAMILY = 'STANDARD_S'
     STORAGE_SIZE_GB = 20
     AUTHENTICATION_AUTHORITY = POSTGRES
     POSTGRES_VERSION = 17
     NETWORK_POLICY = 'GDEC_PG_NETPOL'
     COMMENT = 'GDEC workshop, attendee <NN>';
   ```
   > **WARNING — ONE-TIME CREDENTIALS:** the result row contains `host`, the `snowflake_admin` and `application` users, and their **one-time** passwords. **Copy the row to a scratch file IMMEDIATELY** — you cannot retrieve them later. If you lose them, you will need to ask the HSE to reset credentials for your instance.

2. Wait for the instance to reach `READY`. Poll with:
   ```sql
   SHOW POSTGRES INSTANCES LIKE 'gdec_pg_<NN>';
   ```
   In the result row, look at the `state` column. When it shows `READY`, continue. (You can also click the instance in **Snowsight → Postgres** and watch the state field there.)

3. From your laptop terminal, connect with `psql` using the `application` user from step 1:
   ```bash
   psql "host=<host> user=application password=<password> dbname=postgres sslmode=require"
   ```

4. **Checkpoint A.** At the `psql` prompt:
   ```sql
   SELECT version();
   ```
   You should see PostgreSQL 17.x.

5. Create a small transactional schema for cart and checkout:
   ```sql
   CREATE SCHEMA IF NOT EXISTS commerce;
   SET search_path TO commerce;

   CREATE TABLE cart (
     cart_id        BIGSERIAL PRIMARY KEY,
     customer_id    BIGINT NOT NULL,
     created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
   );

   CREATE TABLE cart_item (
     cart_item_id   BIGSERIAL PRIMARY KEY,
     cart_id        BIGINT NOT NULL REFERENCES cart(cart_id),
     product_id     BIGINT NOT NULL,
     quantity       INT    NOT NULL CHECK (quantity > 0),
     unit_price     NUMERIC(10,2) NOT NULL
   );

   CREATE TABLE inventory_reservation (
     reservation_id BIGSERIAL PRIMARY KEY,
     product_id     BIGINT NOT NULL,
     quantity       INT    NOT NULL,
     expires_at     TIMESTAMPTZ NOT NULL,
     UNIQUE (product_id, reservation_id)
   );

   CREATE TABLE checkout (
     checkout_id    BIGSERIAL PRIMARY KEY,
     cart_id        BIGINT NOT NULL REFERENCES cart(cart_id),
     paid_at        TIMESTAMPTZ,
     amount         NUMERIC(12,2) NOT NULL,
     status         TEXT NOT NULL CHECK (status IN ('PENDING','PAID','FAILED'))
   );
   ```

6. Run a small load:
   ```sql
   INSERT INTO cart (customer_id)
   SELECT (random()*199)::BIGINT FROM generate_series(1, 200);

   INSERT INTO cart_item (cart_id, product_id, quantity, unit_price)
   SELECT
     (random()*199 + 1)::BIGINT,
     (random()*59)::BIGINT,
     (random()*3 + 1)::INT,
     ROUND((random()*4500 + 150)::NUMERIC, 2)
   FROM generate_series(1, 600);

   INSERT INTO checkout (cart_id, paid_at, amount, status)
   WITH r AS (
     SELECT c.cart_id,
            COALESCE(SUM(ci.quantity * ci.unit_price), 0) AS amount,
            random()                                       AS rnd
     FROM   cart c LEFT JOIN cart_item ci ON ci.cart_id = c.cart_id
     GROUP BY c.cart_id
   )
   SELECT
     cart_id,
     CASE WHEN rnd < 0.7 THEN now() ELSE NULL END                                AS paid_at,
     amount,
     CASE WHEN rnd < 0.7 THEN 'PAID'
          WHEN rnd < 0.9 THEN 'PENDING'
          ELSE 'FAILED' END                                                       AS status
   FROM r;
   ```

7. **Checkpoint B.**
   ```sql
   SELECT status, COUNT(*) FROM checkout GROUP BY 1 ORDER BY 1;
   ```
   You should see roughly **70% PAID, 20% PENDING, 10% FAILED** (±3% per bucket because of the `random()` distribution).

8. Demonstrate transactional behavior. Open a second `psql` window connected to the same instance, then in **window 1**:
   ```sql
   BEGIN;
   UPDATE checkout SET status = 'PAID', paid_at = now() WHERE checkout_id = 1;
   ```
   Don't commit yet. In **window 2**:
   ```sql
   SELECT status FROM checkout WHERE checkout_id = 1;  -- still old value
   ```
   Back in **window 1**:
   ```sql
   COMMIT;
   ```
   Re-run the SELECT in window 2 — it now reflects the commit. You've just verified ACID isolation across sessions.

**Stretch goal.** Create an `idx_cart_item_cart_id` index, then `EXPLAIN ANALYZE` a query that joins `cart` and `cart_item` for a specific customer.

**If you get stuck.**
- *"Connection refused / timeout."* → Your IP isn't in `GDEC_PG_NETPOL`. The HSE has the runbook to add it.
- *"Authentication failed."* → You typed the password wrong, or you're using `snowflake_admin` instead of `application`. Use `application` for app-level work.
- *"`CREATE POSTGRES INSTANCE` permission denied."* → Your role wasn't granted the privilege; HSE will fix in seconds.

**Cleanup (do this only after Lab 5).** See Lab 5 step 9.

---

### Lab 5 — Postgres → Snowflake analytics + Cortex AI (25 min)

**Why it matters for Great Deals.** The transactional system in Lab 4 holds the freshest signal of customer intent. To act on it for analytics or AI, you need it in Snowflake without rebuilding ETL. With `pg_lake` shared Iceberg, Postgres writes Iceberg, Snowflake reads it, and you can run Cortex AI functions on top.

**What you'll learn.**
- How to enable `pg_lake` and create an Iceberg table in Postgres.
- How to create a Snowflake catalog integration of type `SNOWFLAKE_POSTGRES` and read the table.
- How to combine fresh transactional data with historical warehouse data and run a Cortex AI function.

**Pre-check.**
- Your Lab 4 instance `gdec_pg_<NN>` is `READY` and you can `psql` into it.
- Your role has `CREATE INTEGRATION` on the account.
- Your Postgres instance is on `STANDARD_S` (Burstable doesn't support `pg_lake`).

**Steps.**

1. In your `psql` session against `gdec_pg_<NN>`, enable `pg_lake`:
   ```sql
   CREATE EXTENSION IF NOT EXISTS pg_lake CASCADE;
   ```

2. Create an Iceberg table that mirrors paid checkouts joined with cart items:
   ```sql
   CREATE TABLE commerce.checkout_iceberg (
     checkout_id   BIGINT,
     cart_id       BIGINT,
     customer_id   BIGINT,
     paid_at       TIMESTAMPTZ,
     amount        NUMERIC(12,2),
     status        TEXT
   ) USING iceberg;

   INSERT INTO commerce.checkout_iceberg
   SELECT c.checkout_id, c.cart_id, ca.customer_id, c.paid_at, c.amount, c.status
   FROM   commerce.checkout c
   JOIN   commerce.cart     ca ON ca.cart_id = c.cart_id
   WHERE  c.status = 'PAID';
   ```

3. **Checkpoint A.** In `psql`:
   ```sql
   SELECT COUNT(*) FROM commerce.checkout_iceberg;
   ```
   Note the count (should be roughly 140 rows, ±20).

4. Switch to Snowsight. Create a catalog integration that points to your Postgres instance:
   ```sql
   USE ROLE ACCOUNTADMIN;
   CREATE OR REPLACE CATALOG INTEGRATION gdec_pg_cat_<NN>
     CATALOG_SOURCE = SNOWFLAKE_POSTGRES
     TABLE_FORMAT   = ICEBERG
     CATALOG_NAMESPACE = 'commerce'
     REST_CONFIG = (
       POSTGRES_INSTANCE = 'gdec_pg_<NN>'
       CATALOG_NAME = 'postgres'
       ACCESS_DELEGATION_MODE = VENDED_CREDENTIALS
     )
     ENABLED = TRUE;
   ```

5. Create a Snowflake Iceberg table that references the Postgres-managed table:
   ```sql
   USE DATABASE GDEC_DEMO; USE SCHEMA COMMERCE;
   CREATE OR REPLACE ICEBERG TABLE checkout_from_pg_<NN>
     CATALOG = 'gdec_pg_cat_<NN>'
     CATALOG_TABLE_NAME = 'checkout_iceberg'
     AUTO_REFRESH = TRUE;
   ```

6. **Checkpoint B.**
   ```sql
   SELECT COUNT(*) FROM checkout_from_pg_<NN>;
   ```
   The count should match the number you saw in step 3.

7. Combine fresh transactional data with the warehouse `PRODUCT_REVIEWS`. For example, summarize recent reviews for products customers are buying right now:
   ```sql
   WITH hot_customers AS (
     SELECT DISTINCT customer_id
     FROM   GDEC_DEMO.COMMERCE.checkout_from_pg_<NN>
     WHERE  paid_at > DATEADD(day, -7, CURRENT_TIMESTAMP())
   ),
   reviews AS (
     SELECT DISTINCT pr.review_id, pr.product_id, pr.review_text, pr.rating
     FROM   GDEC_DEMO.COMMERCE.PRODUCT_REVIEWS pr
     JOIN   GDEC_DEMO.COMMERCE.ORDER_ITEMS  oi ON oi.product_id = pr.product_id
     JOIN   GDEC_DEMO.COMMERCE.ORDERS       o  ON o.order_id    = oi.order_id
     JOIN   hot_customers hc                   ON hc.customer_id = o.customer_id
   )
   SELECT
     product_id,
     COUNT(*) AS review_count,
     AVG(rating) AS avg_rating,
     SNOWFLAKE.CORTEX.SUMMARIZE(LISTAGG(review_text, ' || ')) AS review_summary
   FROM reviews
   GROUP BY product_id
   ORDER BY review_count DESC
   LIMIT 5;
   ```

8. **Checkpoint C.** You should see 5 rows; each `REVIEW_SUMMARY` should be a short paragraph.

9. **Cleanup** (run in Snowsight as `ACCOUNTADMIN`):
   ```sql
   DROP ICEBERG TABLE IF EXISTS GDEC_DEMO.COMMERCE.checkout_from_pg_<NN>;
   DROP CATALOG INTEGRATION IF EXISTS gdec_pg_cat_<NN>;
   DROP POSTGRES INSTANCE IF EXISTS gdec_pg_<NN>;
   ```

**Stretch goal.** Replace `SUMMARIZE` with `AI_CLASSIFY(review_text, ['quality', 'shipping', 'price', 'support'])` and aggregate the resulting categories per product.

**If you get stuck.**
- *"`pg_lake` extension does not exist."* → You provisioned Burstable instead of Standard. Drop and recreate at `STANDARD_S`.
- *"Catalog integration fails."* → Confirm `POSTGRES_INSTANCE` value matches the SHOW POSTGRES INSTANCES name exactly.
- *"`SELECT` from `checkout_from_pg_<NN>` returns 0 rows."* → Run `ALTER ICEBERG TABLE checkout_from_pg_<NN> REFRESH;` and retry.
