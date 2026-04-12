-- Snowflake setup for the supported Glue REST / S3 Tables bridge bundle.
-- Fill in the inputs below, then run the script as ACCOUNTADMIN.
--
-- Canonical naming inputs:
--   CUSTOMER_SLUG
--   DATASET_SLUG
--   ENVIRONMENT
--
-- Derived defaults:
--   NAMESPACE        = <customer_slug>_<dataset_slug>
--   CATALOG_TABLE    = <dataset_slug>_service_hour
--   INTEGRATION_NAME = <CUSTOMER>_S3TABLES_GLUE_REST_INT_<ENVIRONMENT>
--   ICEBERG_TABLE    = <CUSTOMER>_<DATASET>_SERVICE_HOUR
--
-- If the customer needs fixed Snowflake object names instead, edit the SET
-- statements below after the derived values.

set WAREHOUSE_NAME          = 'TODO_WAREHOUSE';
set DATABASE_NAME           = 'TODO_DATABASE';
set SCHEMA_NAME             = 'TODO_SCHEMA';
set AWS_ACCOUNT_ID          = 'TODO_AWS_ACCOUNT_ID';
set TABLE_BUCKET_NAME       = 'TODO_TABLE_BUCKET_NAME';
set SNOWFLAKE_READ_ROLE_ARN = 'TODO_SNOWFLAKE_READ_ROLE_ARN';
set SERVICE_FILTER          = 'TODO_SERVICE_FILTER';

set CUSTOMER_SLUG = 'TODO_CUSTOMER_SLUG';
set DATASET_SLUG  = 'logs';
set ENVIRONMENT   = 'customer';

set NORMALIZED_CUSTOMER_SLUG = (
  select replace($CUSTOMER_SLUG, '-', '_')
);
set NORMALIZED_DATASET_SLUG = (
  select replace($DATASET_SLUG, '-', '_')
);
set NORMALIZED_ENVIRONMENT = (
  select replace($ENVIRONMENT, '-', '_')
);

set NAMESPACE = (
  select $NORMALIZED_CUSTOMER_SLUG || '_' || $NORMALIZED_DATASET_SLUG
);
set CATALOG_TABLE_NAME = (
  select $NORMALIZED_DATASET_SLUG || '_service_hour'
);
set INTEGRATION_NAME = (
  select upper($NORMALIZED_CUSTOMER_SLUG || '_S3TABLES_GLUE_REST_INT_' || $NORMALIZED_ENVIRONMENT)
);
set ICEBERG_TABLE_NAME = (
  select upper($NORMALIZED_CUSTOMER_SLUG || '_' || $NORMALIZED_DATASET_SLUG || '_SERVICE_HOUR')
);
set CATALOG_NAME = (
  select $AWS_ACCOUNT_ID || ':s3tablescatalog/' || $TABLE_BUCKET_NAME
);

use role ACCOUNTADMIN;
use warehouse identifier($WAREHOUSE_NAME);

create database if not exists identifier($DATABASE_NAME);
use database identifier($DATABASE_NAME);

create schema if not exists identifier($SCHEMA_NAME);
use schema identifier($SCHEMA_NAME);

-- 1. Catalog integration to AWS Glue Iceberg REST.
-- The first run creates the integration and exposes the Snowflake IAM user ARN
-- plus external ID through DESCRIBE INTEGRATION. Re-running this script after
-- the AWS trust policy is updated is safe because IF NOT EXISTS avoids
-- rotating the external ID again.
--
-- If you intentionally need to change integration-level properties after the
-- integration already exists, recreate it deliberately and then refresh the
-- AWS trust policy with the new external ID.
create catalog integration if not exists identifier($INTEGRATION_NAME)
  catalog_source = ICEBERG_REST
  table_format = ICEBERG
  catalog_namespace = $NAMESPACE
  rest_config = (
    catalog_uri = 'https://glue.us-east-1.amazonaws.com/iceberg'
    catalog_api_type = AWS_GLUE
    catalog_name = $CATALOG_NAME
    access_delegation_mode = VENDED_CREDENTIALS
  )
  rest_authentication = (
    type = SIGV4
    sigv4_iam_role = $SNOWFLAKE_READ_ROLE_ARN
    sigv4_signing_region = 'us-east-1'
  )
  enabled = true;

-- 2. Inspect the generated trust details and wire them into the AWS IAM role.
describe integration identifier($INTEGRATION_NAME);

-- 3. Optional catalog-linked database.
-- create database if not exists identifier($LINKED_DATABASE_NAME)
--   linked_catalog = (
--     catalog = $INTEGRATION_NAME
--   );

-- 4. Or create a direct table object in the current schema.
-- If this is the first Snowflake-side run, the statement below can still fail
-- until:
--   * the AWS trust policy is locked with the Snowflake IAM user ARN and
--     external ID from DESCRIBE INTEGRATION
--   * the first Glue replace run has created the catalog table in S3 Tables
--   * Lake Formation grants have been applied on that table
--
-- After those steps, rerun this same script. The integration will be reused
-- and only the table creation plus sanity checks will advance.
create or replace iceberg table identifier($ICEBERG_TABLE_NAME)
  catalog = $INTEGRATION_NAME
  catalog_namespace = $NAMESPACE
  catalog_table_name = $CATALOG_TABLE_NAME
  auto_refresh = true;

-- 5. Sanity checks.
select count(*) from identifier($ICEBERG_TABLE_NAME);

select
  min(ts) as min_ts,
  max(ts) as max_ts,
  count(*) as row_count
from identifier($ICEBERG_TABLE_NAME);

select
  ts,
  service,
  substr(message_text, 1, 160) as message_snippet
from identifier($ICEBERG_TABLE_NAME)
order by ts desc
limit 20;

-- 6. BigPanda-style benchmark starter shapes.
select count(*)
from identifier($ICEBERG_TABLE_NAME)
where service = $SERVICE_FILTER
  and ts >= dateadd('hour', -2, current_timestamp())
  and (
    message_text ilike '%error%'
    or message_text ilike '%exception%'
  );

select
  date_trunc('minute', ts) as minute_bucket,
  service,
  count(*) as row_count
from identifier($ICEBERG_TABLE_NAME)
where service = $SERVICE_FILTER
  and ts >= dateadd('hour', -2, current_timestamp())
group by 1, 2
order by 1 desc
limit 200;

select count(*)
from identifier($ICEBERG_TABLE_NAME)
where service = $SERVICE_FILTER
  and ts >= dateadd('hour', -6, current_timestamp())
  and try_parse_json(body_json_text):level::string = 'error';
