-- =============================================================================
-- BRONZE INGESTION AUDIT — volume + quality, in one historical log
-- =============================================================================
--- Run this after each pipeline update 
-- =============================================================================
 
CREATE TABLE IF NOT EXISTS week6.bronze.ingestion_audit_log (
  run_ts                 TIMESTAMP,
  table_name              STRING,
  cumulative_rows          BIGINT,  -- total rows in the table as of this run
  newly_processed          BIGINT,  -- rows added since the last logged run
  null_key_rows            BIGINT,  -- rows failing the PK/composite-key presence check
  duplicate_key_rows       BIGINT,  -- COUNT(*) - COUNT(DISTINCT key) -- this is what test3's 1k seeded duplicates should show up as
  rescued_rows             BIGINT,  -- rows where _rescued_data IS NOT NULL
  domain_check_fail_rows   BIGINT   -- rows failing a table-specific range/domain check (0 where none apply)
) USING DELTA;
 
-- run this after each pipeline update
INSERT INTO week6.bronze.ingestion_audit_log
SELECT
  CURRENT_TIMESTAMP() AS run_ts,
  t.table_name,
  t.cumulative_rows,
  t.cumulative_rows - COALESCE(prev.last_cumulative, 0) AS newly_processed,
  t.null_key_rows,
  t.duplicate_key_rows,
  t.rescued_rows,
  t.domain_check_fail_rows
FROM (
  SELECT'aisles' AS table_name,
    COUNT(*) AS cumulative_rows,
    COUNT_IF(TRY_CAST(aisle_id AS BIGINT) IS NULL OR TRY_CAST(aisle_id AS BIGINT) <= 0) AS null_key_rows,
    COUNT(*) - COUNT(DISTINCT aisle_id) AS duplicate_key_rows,
    COUNT_IF(_rescued_data IS NOT NULL) AS rescued_rows,
    0 AS domain_check_fail_rows
  FROM week6.bronze.aisles
  UNION ALL
  SELECT
    'departments',
    COUNT(*),
    COUNT_IF(TRY_CAST(department_id AS BIGINT) IS NULL OR TRY_CAST(department_id AS BIGINT) <= 0),
    COUNT(*) - COUNT(DISTINCT department_id),
    COUNT_IF(_rescued_data IS NOT NULL),
    0
  FROM week6.bronze.departments
  UNION ALL
  SELECT
    'orders',
    COUNT(*),
    COUNT_IF(TRY_CAST(order_id AS BIGINT) IS NULL OR TRY_CAST(order_id AS BIGINT) <= 0),
    COUNT(*) - COUNT(DISTINCT order_id),
    COUNT_IF(_rescued_data IS NOT NULL),
    COUNT_IF(
      TRY_CAST(user_id AS BIGINT) IS NULL OR TRY_CAST(user_id AS BIGINT) <= 0
      OR TRY_CAST(order_number AS INT) IS NULL OR TRY_CAST(order_number AS INT) <= 0
      OR TRY_CAST(order_dow AS INT) NOT BETWEEN 0 AND 6
      OR TRY_CAST(order_hour_of_day AS INT) NOT BETWEEN 0 AND 23
      OR (days_since_prior_order IS NOT NULL AND TRY_CAST(days_since_prior_order AS DOUBLE) < 0)
    )
  FROM week6.bronze.orders
  UNION ALL
  SELECT 'order_products_prior',
    COUNT(*),
    COUNT_IF(
      TRY_CAST(order_id AS BIGINT) IS NULL OR TRY_CAST(order_id AS BIGINT) <= 0
      OR TRY_CAST(product_id AS BIGINT) IS NULL OR TRY_CAST(product_id AS BIGINT) <= 0
    ),
    COUNT(*) - COUNT(DISTINCT CONCAT(order_id, '-', product_id)),
    COUNT_IF(_rescued_data IS NOT NULL),
    COUNT_IF(
      (add_to_cart_order IS NOT NULL AND TRY_CAST(add_to_cart_order AS INT) <= 0)
      OR (reordered IS NOT NULL AND reordered NOT IN ('0', '1'))
    )
  FROM week6.bronze.order_products_prior
  UNION ALL
  SELECT 'order_products_train',
    COUNT(*),
    COUNT_IF(
      TRY_CAST(order_id AS BIGINT) IS NULL OR TRY_CAST(order_id AS BIGINT) <= 0
      OR TRY_CAST(product_id AS BIGINT) IS NULL OR TRY_CAST(product_id AS BIGINT) <= 0),
    COUNT(*) - COUNT(DISTINCT CONCAT(order_id, '-', product_id)),
    COUNT_IF(_rescued_data IS NOT NULL),
    COUNT_IF(
      (add_to_cart_order IS NOT NULL AND TRY_CAST(add_to_cart_order AS INT) <= 0)
      OR (reordered IS NOT NULL AND reordered NOT IN ('0', '1')))
  FROM week6.bronze.order_products_train
  UNION ALL
  SELECT 'products', COUNT(*),
    COUNT_IF(TRY_CAST(product_id AS BIGINT) IS NULL OR TRY_CAST(product_id AS BIGINT) <= 0),
    COUNT(*) - COUNT(DISTINCT product_id),
    COUNT_IF(_rescued_data IS NOT NULL),
    COUNT_IF(
      TRY_CAST(aisle_id AS BIGINT) IS NULL OR TRY_CAST(aisle_id AS BIGINT) <= 0
      OR TRY_CAST(department_id AS BIGINT) IS NULL OR TRY_CAST(department_id AS BIGINT) <= 0    )
  FROM week6.bronze.products) as t
LEFT JOIN (
  SELECT table_name, MAX(cumulative_rows) AS last_cumulative
  FROM week6.bronze.ingestion_audit_log
  GROUP BY table_name) as prev
ON t.table_name = prev.table_name;
 
 SELECT  * FROM week6.bronze.ingestion_audit_log;

 -- =============================================================================
-- TRACE: duplicates introduced per batch (read-only, run anytime after the
-- INSERT above has logged at least two runs for a table)
-- =============================================================================
-- duplicate_key_rows above is CUMULATIVE -- COUNT(*) over the whole table as
-- it stands at that run, not "how many duplicates did the batch I just
-- loaded add." To see which run introduced (or worsened) duplication, diff
-- consecutive runs per table with LAG(). A positive new_duplicates value on
-- the run right after loading a test batch means that batch is the culprit.
-- =============================================================================
SELECT
  table_name,
  run_ts,
  cumulative_rows,
  duplicate_key_rows,
  duplicate_key_rows - LAG(duplicate_key_rows) OVER (
    PARTITION BY table_name ORDER BY run_ts
  ) AS new_duplicates_this_batch
FROM week6.bronze.ingestion_audit_log
ORDER BY table_name, run_ts;

-- =============================================================================
-- DRILL-DOWN: once a batch is implicated above, find the actual duplicate
-- rows -- and which batches they came from -- by grouping on the same key
-- each table's duplicate_key_rows uses, then joining back to list every
-- copy with its ingestion provenance. Run one at a time, table swapped as
-- needed
-- =============================================================================
 
-- aisles: single-column key
WITH dup_keys AS (
  SELECT aisle_id
  FROM week6.bronze.aisles
  GROUP BY aisle_id
  HAVING COUNT(*) > 1
)
SELECT a.aisle_id, a._ingested_at, a._source_file_name
FROM week6.bronze.aisles a
JOIN dup_keys d ON d.aisle_id = a.aisle_id
ORDER BY a.aisle_id, a._ingested_at;
 
-- departments: single-column key
WITH dup_keys AS (
  SELECT department_id
  FROM week6.bronze.departments
  GROUP BY department_id
  HAVING COUNT(*) > 1
)
SELECT d2.department_id, d2._ingested_at, d2._source_file_name
FROM week6.bronze.departments d2
JOIN dup_keys d ON d.department_id = d2.department_id
ORDER BY d2.department_id, d2._ingested_at;
 
-- products: single-column key
WITH dup_keys AS (
  SELECT product_id
  FROM week6.bronze.products
  GROUP BY product_id
  HAVING COUNT(*) > 1
)
SELECT p.product_id, p._ingested_at, p._source_file_name
FROM week6.bronze.products p
JOIN dup_keys d ON d.product_id = p.product_id
ORDER BY p.product_id, p._ingested_at;
 
-- orders: single-column key
WITH dup_keys AS (
  SELECT order_id
  FROM week6.bronze.orders
  GROUP BY order_id
  HAVING COUNT(*) > 1
)
SELECT o.order_id, o._ingested_at, o._source_file_name
FROM week6.bronze.orders o
JOIN dup_keys d ON d.order_id = o.order_id
ORDER BY o.order_id, o._ingested_at;
 
-- order_products_prior: composite key
WITH dup_keys AS (
  SELECT order_id, product_id
  FROM week6.bronze.order_products_prior
  GROUP BY order_id, product_id
  HAVING COUNT(*) > 1
)
SELECT op.order_id, op.product_id, op._ingested_at, op._source_file_name
FROM week6.bronze.order_products_prior op
JOIN dup_keys d
  ON d.order_id = op.order_id AND d.product_id = op.product_id
ORDER BY op.order_id, op.product_id, op._ingested_at;
 
-- order_products_train: composite key, identical shape, source table swapped
WITH dup_keys AS (
  SELECT order_id, product_id
  FROM week6.bronze.order_products_train
  GROUP BY order_id, product_id
  HAVING COUNT(*) > 1
)
SELECT ot.order_id, ot.product_id, ot._ingested_at, ot._source_file_name
FROM week6.bronze.order_products_train ot
JOIN dup_keys d
  ON d.order_id = ot.order_id AND d.product_id = ot.product_id
ORDER BY ot.order_id, ot.product_id, ot._ingested_at;

CREATE TABLE IF NOT EXISTS week6.silver.silver_ingestion_audit_log (
  run_ts                TIMESTAMP,
  table_name              STRING,
  bronze_rows_in_scope     BIGINT,  -- Bronze cumulative rows, scoped identically to this table's *_clean logic (e.g. eval_set != 'test' for orders) -- NOT week6.bronze.ingestion_audit_log.cumulative_rows, see header note
  silver_rows              BIGINT   -- cumulative rows in the corresponding *_clean STREAMING TABLE as of this run
) USING DELTA;
 

-- run this after each pipeline update
INSERT INTO week6.silver.silver_ingestion_audit_log
SELECT
  CURRENT_TIMESTAMP() AS run_ts,
  table_name,
  bronze_rows_in_scope,
  silver_rows
FROM (
 
  SELECT
    'orders' AS table_name,
    (SELECT COUNT(*) FROM week6.bronze.orders WHERE eval_set != 'test')   AS bronze_rows_in_scope,
    (SELECT COUNT(*) FROM week6.silver.orders_clean) AS silver_rows
  UNION ALL
  SELECT
    'order_products_prior',
    (SELECT COUNT(*) FROM week6.bronze.order_products_prior),
    (SELECT COUNT(*) FROM week6.silver.order_products_prior_clean)
  UNION ALL
  SELECT
    'order_products_train',
    (SELECT COUNT(*) FROM week6.bronze.order_products_train),
    (SELECT COUNT(*) FROM week6.silver.order_products_train_clean)
 
);
 SELECT  * FROM  week6.silver.silver_ingestion_audit_log;
