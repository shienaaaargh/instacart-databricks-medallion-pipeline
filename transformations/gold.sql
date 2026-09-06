--schema

CREATE OR REFRESH MATERIALIZED VIEW week6.gold.dim_product AS
SELECT
  p.product_id                                        AS product_key,
  p.product_id,
  p.product_name,
  p.aisle_id,
  COALESCE(a.aisle, 'Unknown Aisle')                  AS aisle_name,
  p.department_id,
  COALESCE(d.department, 'Unknown Department')        AS department_name,
  p.product_quality_flags,
  ARRAY_CONTAINS(p.product_quality_flags, 'missing_name') AS is_missing_name,
  ARRAY_CONTAINS(p.product_quality_flags, 'missing_aisle') AS is_missing_aisle,
  ARRAY_CONTAINS(p.product_quality_flags, 'missing_department')  AS is_missing_department
FROM week6.silver.products_clean p
LEFT JOIN week6.silver.aisles_clean a       ON p.aisle_id = a.aisle_id
LEFT JOIN week6.silver.departments_clean d  ON p.department_id = d.department_id;


CREATE OR REFRESH MATERIALIZED VIEW week6.gold.dim_order AS
SELECT
  order_id AS order_key,
  order_id,
  user_id,
  eval_set,
  order_number,
  order_number = 1 AS is_first_order,  -- derived, not a stored Silver column
  order_dow,
  CASE order_dow -- ASSUMPTION: 0=Sunday
    WHEN 0 THEN 'Sunday'    WHEN 1 THEN 'Monday'
    WHEN 2 THEN 'Tuesday'   WHEN 3 THEN 'Wednesday'
    WHEN 4 THEN 'Thursday'  WHEN 5 THEN 'Friday'
    WHEN 6 THEN 'Saturday'
  END AS order_day_name,  -- NULL if order_dow was invalid/nulled at Silver
  order_dow IN (0, 6) AS is_weekend,      -- NULL propagates the same way if order_dow is NULL
  order_hour_of_day,
  CASE
    WHEN order_hour_of_day BETWEEN 5  AND 11 THEN 'Morning'
    WHEN order_hour_of_day BETWEEN 12 AND 16 THEN 'Afternoon'
    WHEN order_hour_of_day BETWEEN 17 AND 20 THEN 'Evening'
    WHEN order_hour_of_day BETWEEN 21 AND 23
      OR order_hour_of_day BETWEEN 0  AND 4  THEN 'Night'
    ELSE NULL   -- order_hour_of_day was invalid/nulled at Silver
  END AS daypart,
  days_since_prior_order,
  order_quality_flags                                   AS order_quality_flags
FROM week6.silver.orders_clean;


CREATE OR REFRESH MATERIALIZED VIEW week6.gold.fact_order_items AS
SELECT
  oi.order_id                                                          AS order_key,
  oi.product_id                                                        AS product_key,
  o.user_id,
  o.eval_set,
  oi.add_to_cart_order,
  oi.reordered,
  oi.line_item_quality_flags,
  ARRAY_CONTAINS(oi.line_item_quality_flags, 'invalid_cart_order')      AS is_invalid_cart_order,
  ARRAY_CONTAINS(oi.line_item_quality_flags, 'invalid_reordered')       AS is_reordered_imputed  -- reordered was nulled because the source value was neither '0' nor '1'
FROM (
  SELECT * FROM week6.silver.order_products_prior_clean
  UNION ALL
  SELECT * FROM week6.silver.order_products_train_clean
) oi
INNER JOIN week6.silver.orders_clean o ON oi.order_id = o.order_id;


-- =============================================================================
-- GOLD LAYER — BUSINESS QUESTION VIEWS (dashboard-ready)
-- =============================================================================

-- Q1a: Which products are purchased most frequently?
CREATE OR REFRESH MATERIALIZED VIEW week6.gold.vw_product_popularity AS
SELECT
  dp.product_id,
  dp.product_name,
  dp.department_name,
  dp.aisle_name,
  COUNT(*)                       AS times_ordered,
  SUM(f.reordered)               AS times_reordered,
  RANK() OVER (ORDER BY COUNT(*) DESC)        AS popularity_rank
FROM week6.gold.fact_order_items f
JOIN week6.gold.dim_product dp ON f.product_key = dp.product_key
GROUP BY dp.product_id, dp.product_name, dp.department_name, dp.aisle_name;


-- Q1b: Which departments are purchased most frequently?
CREATE OR REFRESH MATERIALIZED VIEW week6.gold.vw_department_popularity AS
SELECT
  dp.department_name,
  COUNT(*)                                                  AS times_ordered,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)        AS pct_of_total_items
FROM week6.gold.fact_order_items f
JOIN week6.gold.dim_product dp ON f.product_key = dp.product_key
GROUP BY dp.department_name
ORDER BY times_ordered DESC;


-- Q1c: Which aisles are purchased most frequently? 
CREATE OR REFRESH MATERIALIZED VIEW week6.gold.vw_aisle_popularity
COMMENT 'Q1c. One row per aisle: order lines and share of all order lines. Drill-down under departments.'
AS
SELECT
  dp.department_name,
  dp.aisle_name,
  COUNT(*)                                                    AS times_ordered,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)          AS pct_of_total_items
FROM week6.gold.fact_order_items f
JOIN week6.gold.dim_product dp ON f.product_key = dp.product_key
GROUP BY dp.department_name, dp.aisle_name;


-- Q2: How does purchasing behavior change by day of week and hour of day?
CREATE OR REFRESH MATERIALIZED VIEW week6.gold.vw_orders_by_dow_hour AS
SELECT
  do.order_day_name,
  do.order_dow,
  do.order_hour_of_day,
  do.daypart,
  COUNT(DISTINCT f.order_key)   AS order_count,
  COUNT(*)                      AS item_count
FROM week6.gold.fact_order_items f
JOIN week6.gold.dim_order do ON f.order_key = do.order_key
GROUP BY do.order_day_name, do.order_dow, do.order_hour_of_day, do.daypart;


-- Q3: Which products have the highest reorder behavior?
CREATE OR REFRESH MATERIALIZED VIEW week6.gold.vw_product_reorder_rate AS
SELECT
  dp.product_id,
  dp.product_name,
  dp.department_name,
  COUNT(*)                                            AS total_orders,
  SUM(CAST(f.reordered AS INT))                       AS reorder_count,
  ROUND(SUM(CAST(f.reordered AS INT)) / COUNT(*), 4)  AS reorder_rate
FROM week6.gold.fact_order_items f
JOIN week6.gold.dim_product dp ON f.product_key = dp.product_key
GROUP BY dp.product_id, dp.product_name, dp.department_name
HAVING COUNT(*) >= 50
ORDER BY reorder_rate DESC
LIMIT 20;


-- Q4: Team's own question — candidate: does basket size vary by day/daypart?
CREATE OR REFRESH MATERIALIZED VIEW week6.gold.vw_basket_size_by_daypart AS
SELECT
  do.order_day_name,
  do.daypart,
  COUNT(*) / COUNT(DISTINCT f.order_key)  AS avg_basket_size
FROM week6.gold.fact_order_items f
JOIN week6.gold.dim_order do ON f.order_key = do.order_key
GROUP BY do.order_day_name, do.daypart;


-- Supporting KPI view — feeds the dashboard's top-row stat tiles.
CREATE OR REFRESH MATERIALIZED VIEW week6.gold.vw_kpi_summary AS
SELECT
  COUNT(DISTINCT f.order_key)                                AS total_orders,
  COUNT(*)                                                   AS total_order_items,
  COUNT(DISTINCT f.product_key)                              AS distinct_products_ordered,
  COUNT(DISTINCT f.user_id)                                  AS distinct_users,
  ROUND(SUM(CAST(f.reordered AS INT)) / COUNT(*), 4)         AS overall_reorder_rate,
  ROUND(COUNT(*) / COUNT(DISTINCT f.order_key), 2)           AS avg_basket_size
FROM week6.gold.fact_order_items f;


-- =============================================================================
-- GOLD LAYER — DATA QUALITY VALIDATION
-- =============================================================================

CREATE OR REFRESH MATERIALIZED VIEW week6.gold.validation_gold AS

-- Test 1: Ensure fact table grain is truly one row per order/product combo
SELECT 
  'grain_is_unique' AS test_name,
  CASE 
    WHEN (SELECT COUNT(*) FROM week6.gold.fact_order_items) = 
         (SELECT COUNT(DISTINCT CONCAT(order_key, '_', product_key)) FROM week6.gold.fact_order_items)
    THEN 'PASS' ELSE 'FAIL' 
  END AS status

UNION ALL

-- Test 2: Ensure no rows were lost during the UNION ALL of prior and train sets
SELECT 
  'fact_matches_silver' AS test_name,
  CASE 
    WHEN (SELECT COUNT(*) FROM week6.gold.fact_order_items) = 
         (
           (SELECT COUNT(*) FROM week6.silver.order_products_prior_clean) + 
           (SELECT COUNT(*) FROM week6.silver.order_products_train_clean)
         )
    THEN 'PASS' ELSE 'FAIL' 
  END AS status

UNION ALL

-- Test 3: Referential integrity check (No orphan products)
SELECT 
  'every_fact_has_product_dim' AS test_name,
  CASE 
    WHEN (
      SELECT COUNT(*) 
      FROM week6.gold.fact_order_items f 
      LEFT JOIN week6.gold.dim_product d ON f.product_key = d.product_key 
      WHERE d.product_key IS NULL
    ) = 0
    THEN 'PASS' ELSE 'FAIL' 
  END AS status

UNION ALL

-- Test 4: Referential integrity check (No orphan orders)
SELECT 
  'every_fact_has_order_dim' AS test_name,
  CASE 
    WHEN (
      SELECT COUNT(*) 
      FROM week6.gold.fact_order_items f 
      LEFT JOIN week6.gold.dim_order d ON f.order_key = d.order_key 
      WHERE d.order_key IS NULL
    ) = 0
    THEN 'PASS' ELSE 'FAIL' 
  END AS status;
