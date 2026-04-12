# Terraform

Terraform package for the current BigPanda Iceberg bridge architecture:

* upload the Glue bridge scripts
* create the Glue IAM role
* create the Glue job
* create the recurring Glue trigger
* optionally create the AWS-side Snowflake read role
* optionally grant Lake Formation `DESCRIBE` / `SELECT` on the target table

This package intentionally stays focused on the supported bridge path.

It does not manage:

* the target S3 Tables bucket
* Snowflake catalog integrations or Iceberg tables

Those stay outside this module:

* [`../snowflake/setup.sql`](../snowflake/setup.sql)

## What it provisions

This package provisions:

* Glue version `5.0`
* direct S3 Tables catalog path
* `bridge.py` as the main script
* `bridge_logic.py` and `checkpoint.py` uploaded as `--extra-py-files`
* recurring `append` runs on `cron(0/5 * * * ? *)`
* checkpoint stored under the source prefix:
  * `<source-prefix>/_checkpoint/<namespace>/<table>/processed-files.json`
* optional AWS-side Snowflake read role:
  * `AmazonS3TablesReadOnlyAccess`
  * Glue read
  * Lake Formation `GetDataAccess`
  * optional LF table grants for both the Snowflake role and Snowflake IAM user

## Files

* `versions.tf`
* `variables.tf`
* `main.tf`
* `outputs.tf`
* `terraform.tfvars.example`

Use `terraform.tfvars.example` as the canonical handoff file.
It includes:

* every required input
* common runtime overrides
* the Snowflake bootstrap / trust-lock / LF-grant phase toggles

## Inputs

Required:

* `environment`
* `customer_slug`
* `artifact_bucket`
* `artifact_prefix`
* `source_bucket`
* `source_prefix`
* `table_bucket_arn`
* `s3tables_runtime_jar_s3_uri`

Key optional inputs:

* `dataset_slug`
* `namespace`
* `table_name`
* `catalog_name`
* `schedule_expression`
* `create_schedule`
* `schedule_enabled`
* `worker_type`
* `number_of_workers`
* `timeout_minutes`
* `create_snowflake_read_role`
* `snowflake_iam_user_arn`
* `snowflake_bootstrap_principal_arn`
* `snowflake_external_id`
* `snowflake_bootstrap_trust_enabled`
* `grant_snowflake_lakeformation_permissions`
* `tags`

## Usage

```hcl
module "iceberg_bridge" {
  source = "git::ssh://git@github.com/<org>/sawmills-iceberg-bridge.git//terraform?ref=<release-tag>"

  environment                 = "customer"
  customer_slug               = "acme"
  dataset_slug                = "logs"
  artifact_bucket             = "TODO_ARTIFACT_BUCKET"
  artifact_prefix             = "iceberg-bridge/customer"
  source_bucket               = "TODO_SOURCE_BUCKET"
  source_prefix               = "TODO_SOURCE_PREFIX"
  table_bucket_arn            = "arn:aws:s3tables:TODO_REGION:TODO_AWS_ACCOUNT_ID:bucket/TODO_TABLE_BUCKET_NAME"
  s3tables_runtime_jar_s3_uri = "s3://TODO_ARTIFACT_BUCKET/TODO_RUNTIME_JAR_PREFIX/s3-tables-catalog-for-iceberg-runtime-0.1.8.jar"
  create_snowflake_read_role  = true
  snowflake_bootstrap_trust_enabled = true

  tags = {
    ManagedBy   = "terraform"
    Environment = "customer"
  }
}
```

## Naming defaults

The module derives the customer-facing names from a small canonical input set:

* namespace: `<customer_slug>_<dataset_slug>`
* table name: `<dataset_slug>_service_hour`
* Glue job name: `<name_prefix>-<customer_slug>-<environment>`
* Glue role name: `<name_prefix>-<customer_slug>-glue-<environment>`
* Snowflake read role name: `<name_prefix>-<customer_slug>-snowflake-<environment>`

Hyphens in `customer_slug` and `dataset_slug` are normalized to underscores for
Iceberg and Snowflake identifiers.

If a customer already has strict naming standards, override any of these with:

* `job_name`
* `glue_role_name`
* `trigger_name`
* `snowflake_read_role_name`
* `namespace`
* `table_name`

For a true first apply, `snowflake_iam_user_arn` can stay unset.
When bootstrap trust is enabled, the module temporarily trusts the table bucket
account root, purely so the role exists before Snowflake generates the real
IAM user ARN and external ID.

## Apply flow

1. Ensure the target S3 Tables bucket already exists.
2. Ensure the runtime jar already exists at `s3tables_runtime_jar_s3_uri`.
3. First apply:
   * bridge resources
   * optional Snowflake read role in bootstrap trust mode
4. Run the Snowflake-side setup from [`../snowflake/setup.sql`](../snowflake/setup.sql).
5. Read the Snowflake-generated external ID from `DESCRIBE INTEGRATION`.
6. Read the Snowflake-generated IAM user ARN from `DESCRIBE INTEGRATION`.
7. Re-apply with:
   * `snowflake_iam_user_arn` set
   * `snowflake_external_id` set
   * `snowflake_bootstrap_trust_enabled = false`
8. Run the first one-off Glue rebuild with `MODE=replace` so the S3 Tables
   catalog table exists.
9. Re-apply with:
   * `grant_snowflake_lakeformation_permissions = true`
10. Re-run [`../snowflake/setup.sql`](../snowflake/setup.sql) to create or
    refresh the Snowflake Iceberg table without rotating the integration trust.
11. Validate freshness with customer-specific queries against the source and Iceberg paths.

The Snowflake/AWS trust handshake is intentionally two-phase:

* Snowflake generates the external ID
* AWS IAM trust consumes that external ID

Do not leave bootstrap trust enabled after the integration exists.

Recommended variable-file flow:

1. Start from `terraform.tfvars.example`.
2. Phase 1:
   * keep `snowflake_bootstrap_trust_enabled = true`
   * leave `snowflake_iam_user_arn` unset
   * leave `snowflake_external_id` unset
   * keep `grant_snowflake_lakeformation_permissions = false`
3. Phase 2:
   * set `snowflake_iam_user_arn`
   * set `snowflake_external_id`
   * change `snowflake_bootstrap_trust_enabled = false`
4. Phase 3:
   * set `grant_snowflake_lakeformation_permissions = true`

For larger historical bootstrap backfills, temporarily raise
`number_of_workers` for the one-off `replace` run, then scale it back down for
steady-state scheduled `append`.

## Sizing guidance

Use different worker sizing for the two phases:

* bootstrap backfill
  * one-time `replace`
  * sized for the full historical source prefix
* steady-state append
  * recurring scheduled `append`
  * sized for ongoing new-file volume only

Starting points:

* small backlog: `2 x G.1X`
* medium backlog: `5 x G.1X`
* large backlog: `10 x G.1X` for the first `replace`

After the first successful `replace`:

* reduce `number_of_workers`
* keep scheduled `append` sized for normal ingestion, not for the initial catch-up

Common symptom of under-sizing:

* the bootstrap `replace` runs for a long time before checkpoint creation, even
  though the same deployment handles incremental `append` runs normally

## Replace run

The recurring trigger always runs `append`.

For rebuilds:

1. disable the trigger
2. start a one-off Glue run with `MODE=replace`
3. refresh Snowflake
4. re-enable the trigger

The module output `manual_replace_arguments` gives the exact argument map for
that one-off run.

## Customer handoff scope

Good to expose:

* `terraform/`
* `glue_job/`
* `snowflake/setup.sql`
* `CUSTOMER_HANDOFF.md`

Do not expose as part of the customer bundle:

* local `terraform.tfstate*`
* environment-specific benchmark or result documents

## Validation

Recommended local checks:

```bash
terraform fmt -recursive
terraform init -backend=false
terraform validate
```
