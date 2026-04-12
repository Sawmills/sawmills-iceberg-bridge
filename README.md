# Sawmills Iceberg Bridge

Bridge bundle for mirroring Parquet files from S3 into an Iceberg table in
Amazon S3 Tables, then querying that table from Snowflake through AWS Glue
REST.

This repo packages the current supported path:

1. source Parquet files land in S3
2. AWS Glue reads only new files
3. Glue writes into an Iceberg table in S3 Tables
4. Snowflake reads that table through a Glue REST catalog integration

## Who this is for

Use this repo when:

* your source data already lands as Parquet in S3
* you want Iceberg file pruning and Parquet row-group pruning in Snowflake
* you want a low-risk bridge before considering direct native Iceberg writes

Do not use this repo when:

* you need sub-minute streaming freshness
* you need true row-by-row streaming rather than scheduled micro-batch ingestion
* you want this repo to create the S3 Tables bucket itself
* you want Snowflake objects fully managed by Terraform in this repo

## What is here

* [`terraform/`](terraform/)
  AWS-side deployment module
* [`glue_job/`](glue_job/)
  Glue Spark bridge logic
* [`snowflake/setup.sql`](snowflake/setup.sql)
  Snowflake-side integration and table setup template
* [`CUSTOMER_HANDOFF.md`](CUSTOMER_HANDOFF.md)
  deployment checklist for customer installs

## What it manages

This repo manages:

* Glue job script uploads
* Glue IAM role
* Glue job
* recurring Glue trigger
* optional AWS-side Snowflake read role
* optional Lake Formation `DESCRIBE` and `SELECT` grants on the target table

This repo does not manage:

* the source bucket or source prefix
* the target S3 Tables bucket
* Snowflake catalog integrations or Iceberg tables through Terraform
* customer-specific benchmark artifacts or environment-specific runbooks

## How it works

The bridge supports two modes:

* `replace`
  * rebuilds the target table from the full source prefix
  * preserves Iceberg table identity with `TRUNCATE TABLE`
  * refreshes checkpoint state from the rebuilt source set
* `append`
  * lists source Parquet files
  * skips files already recorded in the checkpoint
  * reads only new files
  * persists checkpoint updates only after a successful append

Checkpoint path:

* default:
  * `<source-prefix>/_checkpoint/<namespace>/<table>/processed-files.json`

The recurring trigger always runs `append`.
Use `replace` only for controlled rebuilds.

## Naming model

The happy path is slug-driven.

Canonical inputs:

* `customer_slug`
* `dataset_slug`
* `environment`

Derived defaults:

* namespace:
  * `<customer_slug>_<dataset_slug>`
* catalog table name:
  * `<dataset_slug>_service_hour`
* Glue job name:
  * `<name_prefix>-<customer_slug>-<environment>`
* Glue role name:
  * `<name_prefix>-<customer_slug>-glue-<environment>`
* Snowflake read role name:
  * `<name_prefix>-<customer_slug>-snowflake-<environment>`

Hyphens are normalized to underscores for Iceberg and Snowflake identifiers.

If a customer already has fixed naming standards, override the explicit name
inputs in [`terraform/`](terraform/).

## Prerequisites

Before the first apply, have:

* a source bucket and source prefix with Parquet files
* an existing S3 Tables bucket
* an artifact bucket for Glue scripts and the runtime jar
* the S3 Tables runtime jar already uploaded
* an AWS account where Glue, Lake Formation, and S3 Tables are available
* a Snowflake account where you can run `ACCOUNTADMIN` setup steps

## Versioning

Customers should consume a pinned git tag, not floating `main`.

Use:

* a release tag in the Terraform module source
* the matching repo contents for `snowflake/setup.sql`
* the matching handoff checklist in [`CUSTOMER_HANDOFF.md`](CUSTOMER_HANDOFF.md)

## Quick start

### 1. Fill in Terraform inputs

Start from:

* [`terraform/terraform.tfvars.example`](terraform/terraform.tfvars.example)

At minimum, set:

* `environment`
* `customer_slug`
* `artifact_bucket`
* `artifact_prefix`
* `source_bucket`
* `source_prefix`
* `table_bucket_arn`
* `s3tables_runtime_jar_s3_uri`

### 2. Bootstrap AWS resources

Run the Terraform module in [`terraform/`](terraform/).

First apply should:

* create bridge resources
* optionally create the Snowflake read role
* leave `snowflake_bootstrap_trust_enabled = true`
* leave `snowflake_external_id` unset
* leave `grant_snowflake_lakeformation_permissions = false`

### 3. Create the Snowflake integration

Use:

* [`snowflake/setup.sql`](snowflake/setup.sql)

That script:

* derives Snowflake object names from the same slug model
* creates the Glue REST catalog integration
* can be rerun safely after the AWS trust policy is updated
* creates the direct Iceberg table once the trust policy is ready
* runs basic sanity queries after the table exists

Important:

* on the first run, capture the output of:
  * `DESCRIBE INTEGRATION`
* use the Snowflake IAM user ARN and external ID from that output in the
  second Terraform apply

### 4. Lock the AWS trust policy

Re-apply Terraform with:

* `snowflake_external_id` set
* `snowflake_bootstrap_trust_enabled = false`

### 5. Run the first rebuild

Run one Glue job with:

* `MODE=replace`

This creates or refreshes the target table from the full source prefix.
For larger historical backfills, temporarily raise `number_of_workers` for the
replace run, then scale it back down for steady-state append.

### 6. Grant Lake Formation table access

After the table exists, re-apply Terraform with:

* `grant_snowflake_lakeformation_permissions = true`

### 7. Re-run Snowflake setup

Run the same [`snowflake/setup.sql`](snowflake/setup.sql) again.

Because the integration is now created with `IF NOT EXISTS`, the second run:

* reuses the same integration
* does not rotate the external ID
* creates or refreshes the Snowflake Iceberg table cleanly

### 8. Refresh and validate in Snowflake

Refresh or recreate the Snowflake Iceberg table, then verify:

* row count
* min/max `ts`
* benchmark starter queries

### 9. Turn on ongoing ingestion

Enable the recurring Glue trigger.

The supported steady-state mode is:

* scheduled `append`
* checkpointed file discovery
* Snowflake `auto_refresh = true`

This is continuous micro-batch ingestion.
It is not true row-streaming.

## Sizing guidance

There are two different sizing problems:

* bootstrap backfill
  * one-time `replace`
  * reads the full historical source prefix
  * usually needs more workers
* steady-state ingestion
  * recurring `append`
  * reads only files not yet in the checkpoint
  * usually needs fewer workers

Practical starting points:

* small backlog
  * source prefix has a small historical footprint
  * start with `2 x G.1X`
* medium backlog
  * many hours or days of retained Parquet
  * start with `5 x G.1X`
* large backlog
  * large historical catch-up or multi-GB prefix
  * start with `10 x G.1X` for the first `replace`

After the first successful `replace`:

* scale `number_of_workers` back down
* leave steady-state on smaller scheduled `append` workers

Signs the bootstrap backfill is undersized:

* the first `replace` runs for a long time before writing the checkpoint
* the first `replace` makes little visible progress on a large source prefix
* steady-state append is fine, but historical bootstrap is slow

Sizing rule:

* size the initial `replace` for total backlog
* size scheduled `append` for new-file arrival rate

## Rebuild workflow

When you need a full rebuild:

1. disable the recurring trigger
2. start a one-off Glue run with `MODE=replace`
3. refresh Snowflake
4. re-enable the trigger

Do not rebuild by dropping and recreating the S3 Tables table.
That breaks Snowflake object stability.

## Validation

Local validation:

```bash
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
PYTHONPATH=glue_job python3 -m unittest discover -s glue_job/tests -p 'test_*.py' -v
trunk check --all
```

## Trunk

This repo includes Trunk with a narrow repo-shaped lint set:

* `ruff`
* `markdownlint`
* `shellcheck`
* `shfmt`
* `tflint`
* `git-diff-check`

`sqlfluff` is installed but the current Snowflake setup script is ignored,
because it uses valid Snowflake scripting constructs that SQLFluff does not
parse cleanly in this form.

Useful commands:

```bash
trunk check --all
trunk fmt
trunk upgrade
```

## Troubleshooting

### Snowflake cannot read the table

Check:

* the AWS trust policy includes the current Snowflake external ID
* the Snowflake read role has S3 Tables read access
* Lake Formation grants exist on the target namespace and table
* the Snowflake table points at the current logical Iceberg table identity

### Glue keeps re-reading old data

Check:

* the job is running `append`, not `replace`
* the checkpoint file exists
* the checkpoint path matches the resolved namespace and table name

### Rebuild succeeded but Snowflake sees stale data

Check:

* the rebuild used `TRUNCATE TABLE`, not drop/recreate semantics
* Snowflake table refresh ran after the rebuild
* Lake Formation grants still point to the current table

## Customer handoff

Safe to hand off:

* `terraform/`
* `glue_job/`
* `snowflake/setup.sql`
* this `README.md`

Do not hand off:

* local `terraform.tfstate*`
* `.trunk/` cache directories
* environment-specific benchmark or staging result files
