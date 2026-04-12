import sys

from bridge_logic import NORMALIZED_COLUMNS, normalize_log_record
from checkpoint import (
    JsonCheckpointStore,
    derive_checkpoint_uri,
    finalize_successful_run,
    list_source_files,
    select_new_source_files,
)

REQUIRED_ARGS = [
    "JOB_NAME",
    "SOURCE_PATH",
    "CATALOG_NAME",
    "NAMESPACE",
    "TABLE_NAME",
    "TABLE_BUCKET_ARN",
    "MODE",
]


def get_optional_arg(name):
    needle = f"--{name}"
    for index, arg in enumerate(sys.argv):
        if arg == needle and index + 1 < len(sys.argv):
            return sys.argv[index + 1]
    return None


def configure_catalog(spark, catalog_name, table_bucket_arn):
    spark.conf.set(
        f"spark.sql.catalog.{catalog_name}",
        "org.apache.iceberg.spark.SparkCatalog",
    )
    spark.conf.set(
        f"spark.sql.catalog.{catalog_name}.catalog-impl",
        "software.amazon.s3tables.iceberg.S3TablesCatalog",
    )
    spark.conf.set(
        f"spark.sql.catalog.{catalog_name}.warehouse",
        table_bucket_arn,
    )


def ensure_namespace(spark, catalog_name, namespace):
    try:
        spark.sql(f"CREATE NAMESPACE IF NOT EXISTS {catalog_name}.{namespace}")
    except Exception as exc:
        # The S3 Tables Spark catalog can raise an internal namespace error
        # even when the namespace already exists. Continue and let the table
        # create path prove whether the namespace is actually usable.
        print(f"bridge.namespace_warning={exc}")


def clear_target_table_for_replace(spark, target_table):
    # Preserve the Iceberg table identity so Snowflake refresh can keep tracking
    # the same table bucket location across rebuilds.
    spark.sql(f"TRUNCATE TABLE {target_table}")


def create_target_table(spark, target_table):
    spark.sql(
        f"""
        CREATE TABLE IF NOT EXISTS {target_table} (
          ts TIMESTAMP,
          ts_raw STRING,
          service STRING,
          status STRING,
          message_text STRING,
          host STRING,
          source STRING,
          trace_id STRING,
          span_id STRING,
          schema_version STRING,
          body_json_text STRING,
          attributes_hot_text STRING,
          attributes_cold_text STRING,
          tags_hot_text STRING,
          tags_cold_text STRING,
          source_file STRING
        )
        USING iceberg
        PARTITIONED BY (service, hours(ts))
        TBLPROPERTIES (
          'format-version' = '2',
          'write.target-file-size-bytes' = '104857600',
          'write.distribution-mode' = 'hash'
        )
        """
    )


def build_normalized_dataframe(spark, source_df):
    from pyspark.sql import functions as F
    from pyspark.sql import types as T

    schema = T.StructType(
        [
            T.StructField("ts", T.TimestampType(), True),
            T.StructField("ts_raw", T.StringType(), True),
            T.StructField("service", T.StringType(), True),
            T.StructField("status", T.StringType(), True),
            T.StructField("message_text", T.StringType(), True),
            T.StructField("host", T.StringType(), True),
            T.StructField("source", T.StringType(), True),
            T.StructField("trace_id", T.StringType(), True),
            T.StructField("span_id", T.StringType(), True),
            T.StructField("schema_version", T.StringType(), True),
            T.StructField("body_json_text", T.StringType(), True),
            T.StructField("attributes_hot_text", T.StringType(), True),
            T.StructField("attributes_cold_text", T.StringType(), True),
            T.StructField("tags_hot_text", T.StringType(), True),
            T.StructField("tags_cold_text", T.StringType(), True),
            T.StructField("source_file", T.StringType(), True),
        ]
    )

    enriched_df = source_df.withColumn("source_file", F.input_file_name())
    normalized_rows = enriched_df.rdd.map(
        lambda row: normalize_log_record(row.asDict(recursive=True))
    ).filter(lambda row: row is not None)

    return spark.createDataFrame(
        normalized_rows.map(
            lambda row: tuple(row.get(name) for name in NORMALIZED_COLUMNS)
        ),
        schema=schema,
    )


def main():
    from awsglue.context import GlueContext
    from awsglue.job import Job
    from awsglue.utils import getResolvedOptions
    from pyspark.context import SparkContext

    args = getResolvedOptions(sys.argv, REQUIRED_ARGS)

    sc = SparkContext.getOrCreate()
    glue_context = GlueContext(sc)
    spark = glue_context.spark_session
    job = Job(glue_context)
    job.init(args["JOB_NAME"], args)

    catalog_name = args["CATALOG_NAME"]
    namespace = args["NAMESPACE"]
    table_name = args["TABLE_NAME"]
    source_path = args["SOURCE_PATH"]
    mode = args["MODE"].strip().lower()
    checkpoint_uri = get_optional_arg("CHECKPOINT_URI") or derive_checkpoint_uri(
        source_path, namespace, table_name
    )
    checkpoint_store = JsonCheckpointStore(checkpoint_uri)

    configure_catalog(spark, catalog_name, args["TABLE_BUCKET_ARN"])

    target_table = f"{catalog_name}.{namespace}.{table_name}"

    print(f"bridge.mode={mode}")
    print(f"bridge.source_path={source_path}")
    print(f"bridge.target_table={target_table}")
    print(f"bridge.checkpoint_uri={checkpoint_uri}")

    ensure_namespace(spark, catalog_name, namespace)

    discovered_files = list_source_files(source_path)
    print(f"bridge.discovered_files={len(discovered_files)}")

    processed_files_before = set()

    if mode == "replace":
        create_target_table(spark, target_table)
        clear_target_table_for_replace(spark, target_table)
        source_files = discovered_files
    elif mode != "append":
        raise ValueError("MODE must be either 'replace' or 'append'")
    else:
        processed_files_before = checkpoint_store.load()
        source_files = select_new_source_files(discovered_files, processed_files_before)
        print(f"bridge.processed_files={len(processed_files_before)}")
        print(f"bridge.new_files={len(source_files)}")

    if not source_files:
        print("bridge.no_new_files=true")
        job.commit()
        return

    create_target_table(spark, target_table)

    source_df = spark.read.parquet(*source_files)
    normalized_df = build_normalized_dataframe(spark, source_df)

    normalized_df.createOrReplaceTempView("bridge_source_logs")

    spark.sql(
        f"""
        INSERT INTO {target_table}
        SELECT
          ts,
          ts_raw,
          service,
          status,
          message_text,
          host,
          source,
          trace_id,
          span_id,
          schema_version,
          body_json_text,
          attributes_hot_text,
          attributes_cold_text,
          tags_hot_text,
          tags_cold_text,
          source_file
        FROM bridge_source_logs
        """
    )

    print(f"bridge.inserted_source_files={len(source_files)}")
    finalize_successful_run(checkpoint_store, processed_files_before, source_files)

    job.commit()


if __name__ == "__main__":
    main()
