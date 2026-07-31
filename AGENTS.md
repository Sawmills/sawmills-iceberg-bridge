# AGENTS.md

## Project

This repository mirrors Parquet files from S3 into an Iceberg table in Amazon S3 Tables.
Snowflake queries the table through AWS Glue REST.
The bridge uses scheduled micro-batch ingestion.
It does not create the source bucket, source prefix, or S3 Tables bucket.
It does not manage Snowflake catalog integrations or Iceberg tables through Terraform.

## Map

- `glue_job/` contains the Glue Spark bridge, checkpoint code, and tests.
- `terraform/` contains the AWS deployment module and input example.
- `snowflake/setup.sql` contains the Snowflake integration and table setup template.
- `CUSTOMER_HANDOFF.md` is the customer deployment checklist.
- `README.md` describes the supported deployment path and naming model.

## Commands

- Run the first controlled rebuild as one Glue job with `MODE=replace`.
- Use `DESCRIBE INTEGRATION` on the first Snowflake setup run.
- Re-apply Terraform after the Snowflake IAM user ARN and external ID are known.

## Rules

- Use `append` for the recurring Glue trigger.
- Use `replace` only for controlled rebuilds.
- Preserve Iceberg table identity during replacement with `TRUNCATE TABLE`.
- Persist checkpoint updates only after a successful append.
- Keep the default checkpoint under `<source-prefix>/_checkpoint/<namespace>/<table>/processed-files.json`.
- Treat `customer_slug`, `dataset_slug`, and `environment` as canonical naming inputs.
- Normalize hyphens to underscores in Iceberg and Snowflake identifiers.
- Require an existing source bucket, source prefix, S3 Tables bucket, artifact bucket, and runtime jar.
- Upload the S3 Tables runtime jar before deployment.
- Start Snowflake trust bootstrap with `snowflake_bootstrap_trust_enabled = true`.
- Leave `snowflake_external_id` unset during the first apply.
- Leave `grant_snowflake_lakeformation_permissions = false` until the table exists.
- After Snowflake setup, set `snowflake_iam_user_arn` and
  `snowflake_external_id`, then set
  `snowflake_bootstrap_trust_enabled = false`.
- Use a pinned release tag. Do not use floating `main` for customer deployments.
- Keep the Terraform module, `snowflake/setup.sql`, and `CUSTOMER_HANDOFF.md` on the same release.
- Keep customer-specific benchmark artifacts and environment-specific runbooks outside this repository.
- Follow `CUSTOMER_HANDOFF.md` for customer deployment steps.
