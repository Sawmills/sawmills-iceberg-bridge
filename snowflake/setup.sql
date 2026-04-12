-- Snowflake setup for the supported Glue REST / S3 Tables bridge bundle.
-- Fill in the placeholders before running.
--
-- Required values:
--   TODO_WAREHOUSE
--   TODO_DATABASE
--   TODO_SCHEMA
--   TODO_INTEGRATION_NAME
--   TODO_ICEBERG_TABLE_NAME
--   TODO_AWS_ACCOUNT_ID
--   TODO_TABLE_BUCKET_NAME
--   TODO_NAMESPACE
--   TODO_CATALOG_TABLE_NAME
--   TODO_SNOWFLAKE_READ_ROLE_ARN
--   TODO_SERVICE_FILTER

use role ACCOUNTADMIN;
use warehouse TODO_WAREHOUSE;

create database if not exists TODO_DATABASE;
create schema if not exists TODO_DATABASE.TODO_SCHEMA;

use database TODO_DATABASE;
use schema TODO_SCHEMA;

-- 1. Catalog integration to AWS Glue Iceberg REST.
-- For S3 Tables, CATALOG_NAME must be bucket-scoped:
--   <aws-account-id>:s3tablescatalog/<table-bucket-name>
create or replace catalog integration TODO_INTEGRATION_NAME
  catalog_source = ICEBERG_REST
  table_format = ICEBERG
  catalog_namespace = 'TODO_NAMESPACE'
  rest_config = (
    catalog_uri = 'https://glue.us-east-1.amazonaws.com/iceberg'
    catalog_api_type = AWS_GLUE
    catalog_name = 'TODO_AWS_ACCOUNT_ID:s3tablescatalog/TODO_TABLE_BUCKET_NAME'
    access_delegation_mode = VENDED_CREDENTIALS
  )
  rest_authentication = (
    type = SIGV4
    sigv4_iam_role = 'TODO_SNOWFLAKE_READ_ROLE_ARN'
    sigv4_signing_region = 'us-east-1'
  )
  enabled = true;

-- 2. Inspect the generated trust details and wire them into the AWS IAM role.
-- CREATE OR REPLACE rotates the external ID, so refresh the AWS trust policy
-- every time this integration is recreated.
describe integration TODO_INTEGRATION_NAME;

-- 3. Optional catalog-linked database.
-- This is the cleanest way to browse multiple Iceberg tables from the same
-- remote catalog.
-- create database if not exists TODO_LINKED_DATABASE
--   linked_catalog = (
--     catalog = 'TODO_INTEGRATION_NAME'
--   );

-- 4. Or create a direct table object in the current schema.
create or replace iceberg table TODO_ICEBERG_TABLE_NAME
  catalog = 'TODO_INTEGRATION_NAME'
  catalog_namespace = 'TODO_NAMESPACE'
  catalog_table_name = 'TODO_CATALOG_TABLE_NAME'
  auto_refresh = true;

-- 5. Sanity checks.
select count(*) from TODO_ICEBERG_TABLE_NAME;

select
  min(ts) as min_ts,
  max(ts) as max_ts,
  count(*) as row_count
from TODO_ICEBERG_TABLE_NAME;

select
  ts,
  service,
  substr(message_text, 1, 160) as message_snippet
from TODO_ICEBERG_TABLE_NAME
order by ts desc
limit 20;

-- 6. BigPanda-style benchmark starter shapes.
select count(*)
from TODO_ICEBERG_TABLE_NAME
where service = 'TODO_SERVICE_FILTER'
  and ts >= dateadd('hour', -2, current_timestamp())
  and (
    message_text ilike '%error%'
    or message_text ilike '%exception%'
  );

select
  date_trunc('minute', ts) as minute_bucket,
  service,
  count(*) as row_count
from TODO_ICEBERG_TABLE_NAME
where service = 'TODO_SERVICE_FILTER'
  and ts >= dateadd('hour', -2, current_timestamp())
group by 1, 2
order by 1 desc
limit 200;

select count(*)
from TODO_ICEBERG_TABLE_NAME
where service = 'TODO_SERVICE_FILTER'
  and ts >= dateadd('hour', -6, current_timestamp())
  and try_parse_json(body_json_text):level::string = 'error';
