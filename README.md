# Iceberg Bridge

Customer-facing bridge bundle for mirroring Parquet files from S3 into an
Iceberg table in Amazon S3 Tables, then querying that table from Snowflake via
AWS Glue REST.

Exportable bundle contents:

* Glue job script: `glue_job/bridge.py`
* Terraform module: `terraform/`
* Snowflake setup template: `snowflake/setup.sql`

## What it does

* reads a source Parquet prefix from the collector path
* tracks processed source files with an explicit checkpoint
* normalizes the log shape into a query-friendly schema
* writes an isolated Iceberg table in the target S3 Tables catalog
* provides Snowflake setup SQL for catalog integration and validation queries

The supported writer path is the direct S3 Tables catalog path in Glue Spark.

## Glue job

Run the Glue job script in `glue_job/bridge.py` with these required args:

* `JOB_NAME`
* `SOURCE_PATH`
* `CATALOG_NAME`
* `NAMESPACE`
* `TABLE_NAME`
* `TABLE_BUCKET_ARN`
* `MODE`

Optional arg:

* `CHECKPOINT_URI`

Recommended first run:

* `CATALOG_NAME=s3tablesbp`
* `NAMESPACE=<customer_slug>_<dataset_slug>`
* `TABLE_NAME=<dataset_slug>_service_hour`
* `MODE=replace`

Recommended naming model:

* `customer_slug`
* `dataset_slug`
* derive namespace and table name from those
* only override the explicit names if the customer already has fixed standards

Bridge modes:

* `replace`
  * preserves the target Iceberg table identity with `TRUNCATE TABLE`
  * rereads the whole source prefix
  * refreshes checkpoint state from the rebuild
* `append`
  * lists source parquet files under `SOURCE_PATH`
  * filters out files already present in the checkpoint
  * reads only new files
  * updates the checkpoint only after a successful append
  * logs inserted source-file count, not a post-write full-table row count

Checkpoint behavior:

* if `CHECKPOINT_URI` is omitted, the script derives one from the source path:
  * `<source-prefix>/_checkpoint/<namespace>/<table>/processed-files.json`
* current checkpoint format is JSON with a `processed_files` array
* `append` is the supported mode for ongoing ingestion
* `replace` is for rebuilds and controlled benchmark resets
* pause the recurring trigger before `replace`, then resume it after the rebuild

Required Spark runtime settings:

* Glue version `5.0`
* `--datalake-formats iceberg`
* `--extra-jars` pointing at the S3 Tables runtime jar
* `--conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions`

## Snowflake setup

Use `snowflake/setup.sql` to:

* create the Glue REST catalog integration
* create a direct Iceberg table
* run baseline sanity checks and query templates

Important:

* for S3 Tables, `CATALOG_NAME` must be bucket-scoped:
  * `<aws-account-id>:s3tablescatalog/<table-bucket-name>`
* `ACCESS_DELEGATION_MODE = VENDED_CREDENTIALS` is required on the Snowflake
  integration
* `CREATE OR REPLACE CATALOG INTEGRATION` rotates the Snowflake-generated
  external ID, so the AWS trust policy must be refreshed from `DESCRIBE
  INTEGRATION`
* Snowflake refresh stays stable only if the S3 Tables table identity stays
  stable; do not implement rebuilds by dropping and recreating the target table
* the Snowflake AWS role needs both:
  * Glue and Lake Formation read access
  * S3 Tables read access, for example `AmazonS3TablesReadOnlyAccess`

## Customer-safe cut

Include:

* `glue_job/`
* `terraform/`
* `snowflake/setup.sql`

Exclude:

* `terraform.tfstate*`
* environment-specific examples
* environment-specific benchmark queries, runbooks, and result captures
