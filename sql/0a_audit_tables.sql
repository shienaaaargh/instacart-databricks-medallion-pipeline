CREATE TABLE IF NOT EXISTS week6.bronze.ingestion_audit_log (
  run_ts                 TIMESTAMP,
  table_name              STRING,
  cumulative_rows          BIGINT,  -- total rows in the table as of this run
  newly_processed          BIGINT,  -- rows added since the last logged run
  null_key_rows            BIGINT,  -- rows failing the PK/composite-key presence check
  duplicate_key_rows       BIGINT,  -- COUNT(*) - COUNT(DISTINCT key)
  rescued_rows             BIGINT,  -- rows where _rescued_data IS NOT NULL
  domain_check_fail_rows   BIGINT   -- rows failing a table-specific range/domain check (0 where none apply)
) USING DELTA;
 
CREATE TABLE IF NOT EXISTS week6.silver.silver_ingestion_audit_log (
  run_ts                TIMESTAMP,
  table_name              STRING,
  bronze_rows_in_scope     BIGINT,  -- Bronze cumulative rows, scoped identically to this table's *_clean logic (e.g. eval_set != 'test' for orders)
  silver_rows              BIGINT   -- cumulative rows in the corresponding *_clean STREAMING TABLE as of this run
) USING DELTA;
