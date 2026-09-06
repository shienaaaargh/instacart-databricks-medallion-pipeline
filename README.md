<div align="center">

# 🛒 Instacart Lakehouse Pipeline
### End-to-End Medallion Architecture on Databricks

[![Databricks](https://img.shields.io/badge/Platform-Databricks-FF3621?style=for-the-badge&logo=databricks&logoColor=white)](https://databricks.com)
[![Delta Lake](https://img.shields.io/badge/Storage-Delta%20Lake-00ADD8?style=for-the-badge&logo=delta&logoColor=white)](https://delta.io)
[![SQL](https://img.shields.io/badge/Language-SQL-4479A1?style=for-the-badge&logo=postgresql&logoColor=white)](#)
[![Workflows](https://img.shields.io/badge/Orchestration-Databricks%20Workflows-2E8B57?style=for-the-badge)](#)

<p align="center">
  A collaborative data engineering pipeline ingesting, cleansing, and aggregating grocery order data into analytics-ready Delta tables, managed with Databricks Workflows and operational audit logging.
</p>

</div>

---

## ✦ Project Overview

This project implements an end-to-end Lakehouse solution using the **Instacart Market Basket Analysis** dataset on Databricks. It processes order histories, product catalogs, and department hierarchies to provide analytics-ready tables for customer retention and market basket insights.

The data pipeline follows the **Medallion Architecture**, progressing through raw ingestion (Bronze), cleansed data conformance (Silver), and aggregated business metrics (Gold), all governed by automated pre-run and post-run audit tracking.

---

## ✦ Architecture & Data Flow

```text
               ┌───────────────────────────────┐
               │    Raw CSV Files / Sources    │
               └───────────────┬───────────────┘
                               │
                               ▼
 ┌───────────────────────────────────────────────────────────┐
 │                Task 1: audit_table_creation               │
 │        Initializes audit schemas & runtime metadata       │
 └─────────────────────────────┬─────────────────────────────┘
                               │
                               ▼
 ┌───────────────────────────────────────────────────────────┐
 │                Task 2: instacart_pipeline                 │
 │                                                           │
 │   🥉 Bronze Layer: Raw table appends with timestamps      │
 │                          │                                │
 │                          ▼                                │
 │   🥈 Silver Layer: Deduplication, typing & validation     │
 │                          │                                │
 │                          ▼                                │
 │   🥇 Gold Layer: Customer order aggregations & metrics    │
 └─────────────────────────────┬─────────────────────────────┘
                               │
                               ▼
 ┌───────────────────────────────────────────────────────────┐
 │                    Task 3: audit_log                      │
 │    Captures table record counts, execution status & logs  │
 └───────────────────────────────────────────────────────────┘



instacart-databricks-medallion-pipeline/
├── README.md                          # Project documentation and architectural overview
├── sql/
│   ├── 0a_audit_tables.sql            # Pre-flight audit schema setup
│   └── 0b_audit_log.sql               # Post-flight pipeline execution logging
├── transformations/
│   └── transformations.sql            # Medallion SQL transformation scripts
└── workflows/
    └── instacart_trial_run.json       # Exported Databricks Workflow configuration

---

## ✦ Key Engineering Features

- **ACID Transactions**: Stored on Delta Lake to ensure consistency during multi-table writes.
- **Audit & Governance**: Automated logging tracks pipeline execution health and record volume changes.
- **Modular Codebase**: Decoupled SQL scripts for administrative tasks, business logic, and job definitions.
- **Infrastructure as Code**: The complete Databricks Workflow definition is captured in JSON for reproducible deployments.

---

## 👥 Team & Acknowledgments

- **Data Engineering Lead**: [@jg0901] (https://github.com/jg0901) — Pipeline architecture design, coordination, and technical direction.
- **Data Engineering backup dancers**:
[@shienaaaargh](https://github.com/shienaaaargh) — Pipeline replication, end-to-end validation, Gold layer analytics, and Databricks dashboard creation.
[@czekinah] (https://github.com/czekinah) - Code development, pipeline validation, instructor coordination, project alignment, and supplementary research.
[@go-viaaa] (https://github.com/go-viaaa) - Documentation review and project support.
[@merryjoytalento-cmd] ([https://github.com/go-viaaa](https://github.com/merryjoytalento-cmd)) - Raw data profiling, documentation review and project support.
---

<div align="center">

*Developed as part of a hands-on data engineering project on Databricks.*

</div>

