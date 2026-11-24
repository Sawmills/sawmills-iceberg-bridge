# Iceberg Bridge

The Iceberg Bridge mirrors Parquet logs from Amazon S3 into an Apache Iceberg
table in Amazon S3 Tables. Snowflake accesses the table through an AWS Glue
REST catalog integration.

## Language

### Ingestion

**Source Prefix**:
The existing Amazon S3 location under which the bridge discovers Parquet files.

**Micro-Batch**:
A scheduled unit of ingestion that mirrors new source files into the target
table.

**Checkpoint**:
A record of source file paths for a target table, saved after successful
insertion. Append Mode uses it to identify new paths.

**Append Mode**:
An ingestion run that adds rows from source files whose paths are absent from
the Checkpoint. The recurring trigger uses this mode.

**Replace Mode**:
A controlled rebuild that truncates the target table in place and loads all
discovered source files. A successful insert replaces the Checkpoint with the
paths used for the rebuild.

**Normalized Log Record**:
A source log reshaped into the Iceberg Table's columns with a parsed event
timestamp. The bridge skips rows with unusable timestamps.

### Table and Catalog

**Table Bucket**:
An existing Amazon S3 Tables bucket that holds the target Iceberg Table.

**Namespace**:
The grouping in the Iceberg catalog where the bridge creates the target table
and Snowflake looks it up.

**Iceberg Table**:
The destination for normalized logs in the Table Bucket. AWS Glue writes its
rows, and Snowflake queries them through the Catalog Integration.

**Partitioning**:
The grouping of the target table's rows by service and event hour.

**Catalog Integration**:
A Snowflake object that connects to the AWS Glue REST catalog using a
configured read role.

**Lake Formation Table Access**:
Permissions to describe the Iceberg Table and select its rows for Snowflake.
The deployment can grant these after the table exists.

**Automatic Refresh**:
The Snowflake table setting that enables automatic updates of Iceberg
metadata from the catalog.
