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

set NORMALIZED_CUSTOMER_SLUG = replace($CUSTOMER_SLUG, '-', '_');
set NORMALIZED_DATASET_SLUG  = replace($DATASET_SLUG, '-', '_');
set NORMALIZED_ENVIRONMENT   = replace($ENVIRONMENT, '-', '_');

set NAMESPACE = $NORMALIZED_CUSTOMER_SLUG || '_' || $NORMALIZED_DATASET_SLUG;
set CATALOG_TABLE_NAME = $NORMALIZED_DATASET_SLUG || '_service_hour';
set INTEGRATION_NAME = upper(
  $NORMALIZED_CUSTOMER_SLUG || '_S3TABLES_GLUE_REST_INT_' || $NORMALIZED_ENVIRONMENT
);
set ICEBERG_TABLE_NAME = upper(
  $NORMALIZED_CUSTOMER_SLUG || '_' || $NORMALIZED_DATASET_SLUG || '_SERVICE_HOUR'
);
set CATALOG_NAME = $AWS_ACCOUNT_ID || ':s3tablescatalog/' || $TABLE_BUCKET_NAME;

use role ACCOUNTADMIN;
use warehouse identifier($WAREHOUSE_NAME);

create database if not exists identifier($DATABASE_NAME);
use database identifier($DATABASE_NAME);

create schema if not exists identifier($SCHEMA_NAME);
use schema identifier($SCHEMA_NAME);

-- 1. Catalog integration to AWS Glue Iceberg REST.
create or replace catalog integration identifier($INTEGRATION_NAME)
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
-- CREATE OR REPLACE rotates the external ID, so refresh the AWS trust policy
-- every time this integration is recreated.
describe integration identifier($INTEGRATION_NAME);

-- 3. Optional catalog-linked database.
-- create database if not exists identifier($LINKED_DATABASE_NAME)
--   linked_catalog = (
--     catalog = $INTEGRATION_NAME
--   );

-- 4. Or create a direct table object in the current schema.
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
