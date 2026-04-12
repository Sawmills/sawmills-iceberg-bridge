# Customer Handoff

Use this checklist for a fresh customer deployment.

## Inputs

Prepare:

* source bucket and source prefix
* target S3 Tables bucket ARN
* artifact bucket and prefix
* runtime jar S3 URI
* customer slug
* environment name
* Snowflake warehouse, database, and schema

Start from:

* [`terraform/terraform.tfvars.example`](terraform/terraform.tfvars.example)

## Phase 1: Bootstrap AWS

Run Terraform with:

* `snowflake_bootstrap_trust_enabled = true`
* `snowflake_external_id` unset
* `snowflake_iam_user_arn` unset
* `grant_snowflake_lakeformation_permissions = false`

This creates:

* Glue job
* Glue trigger
* Glue role
* Snowflake read role on the AWS side

## Phase 2: Create Snowflake Integration

Run:

* [`snowflake/setup.sql`](snowflake/setup.sql)

From the `DESCRIBE INTEGRATION` output, capture:

* Snowflake IAM user ARN
* Snowflake external ID

## Phase 3: Lock AWS Trust

Re-run Terraform with:

* `snowflake_iam_user_arn` set
* `snowflake_external_id` set
* `snowflake_bootstrap_trust_enabled = false`

## Phase 4: First Backfill

Run one Glue job with:

* `MODE=replace`

If the customer has a large historical backlog, temporarily increase
`number_of_workers` for this run.

Practical starting points:

* small backlog: `2 x G.1X`
* medium backlog: `5 x G.1X`
* large backlog: `10 x G.1X`

After the first successful backfill:

* scale `number_of_workers` back down for steady-state

## Phase 5: Grant Table Access

Re-run Terraform with:

* `grant_snowflake_lakeformation_permissions = true`

## Phase 6: Create Snowflake Table

Run [`snowflake/setup.sql`](snowflake/setup.sql) again.

Because the integration is created with `IF NOT EXISTS`, this rerun:

* reuses the same integration
* avoids rotating the external ID
* creates or refreshes the Snowflake Iceberg table

## Phase 7: Validate

Confirm in Snowflake:

* the table is queryable
* row count is non-zero
* `max(ts)` is current enough for the source dataset

Confirm in AWS:

* the checkpoint file exists
* the checkpoint contains processed file paths

## Phase 8: Ongoing Ingestion

Enable the recurring trigger.

Steady-state behavior:

* scheduled `append`
* checkpointed file discovery
* Snowflake reads the same logical Iceberg table

This is continuous micro-batch ingestion.
It is not row-by-row streaming.

## Rebuilds

For future rebuilds:

1. disable the recurring trigger
2. run a one-off `MODE=replace`
3. refresh Snowflake
4. re-enable the trigger

Do not drop and recreate the S3 Tables table during rebuilds.
