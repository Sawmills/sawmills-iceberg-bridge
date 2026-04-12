data "aws_partition" "current" {}

locals {
  source_prefix_trimmed   = trimsuffix(var.source_prefix, "/")
  artifact_prefix_trimmed = trimsuffix(var.artifact_prefix, "/")
  runtime_jar_uri_trimmed = trimsuffix(var.s3tables_runtime_jar_s3_uri, "/")

  runtime_jar_uri_without_scheme = trimprefix(local.runtime_jar_uri_trimmed, "s3://")
  runtime_jar_path_parts         = split("/", local.runtime_jar_uri_without_scheme)
  runtime_jar_bucket             = local.runtime_jar_path_parts[0]
  runtime_jar_key                = join("/", slice(local.runtime_jar_path_parts, 1, length(local.runtime_jar_path_parts)))
  runtime_jar_parent_prefix      = dirname(local.runtime_jar_key)
  table_bucket_name              = element(split("/", var.table_bucket_arn), 1)
  table_bucket_account_id        = element(split(":", var.table_bucket_arn), 4)
  lakeformation_catalog_id       = "${local.table_bucket_account_id}:s3tablescatalog/${local.table_bucket_name}"

  glue_job_name     = coalesce(var.job_name, "${var.name_prefix}-${var.environment}")
  glue_role_name    = coalesce(var.glue_role_name, "${var.name_prefix}-glue-${var.environment}")
  glue_trigger_name = coalesce(var.trigger_name, "${local.glue_job_name}-every-5m")
  snowflake_role_name = coalesce(
    var.snowflake_read_role_name,
    "${var.name_prefix}-snowflake-${var.environment}",
  )

  source_path     = "s3://${var.source_bucket}/${local.source_prefix_trimmed}/"
  checkpoint_uri  = "s3://${var.source_bucket}/${local.source_prefix_trimmed}/_checkpoint/${var.namespace}/${var.table_name}/processed-files.json"
  temp_dir        = "s3://${var.artifact_bucket}/${local.artifact_prefix_trimmed}/tmp/"
  bridge_script   = "${local.artifact_prefix_trimmed}/glue_job/bridge.py"
  bridge_logic    = "${local.artifact_prefix_trimmed}/glue_job/bridge_logic.py"
  checkpoint_code = "${local.artifact_prefix_trimmed}/glue_job/checkpoint.py"

  source_object_arn   = "arn:${data.aws_partition.current.partition}:s3:::${var.source_bucket}/${local.source_prefix_trimmed}/*"
  artifact_object_arn = "arn:${data.aws_partition.current.partition}:s3:::${var.artifact_bucket}/${local.artifact_prefix_trimmed}/*"
  runtime_jar_arn     = "arn:${data.aws_partition.current.partition}:s3:::${local.runtime_jar_bucket}/${local.runtime_jar_key}"

  source_list_prefixes = [
    "${local.source_prefix_trimmed}/*",
  ]

  artifact_list_prefixes = [
    "${local.artifact_prefix_trimmed}/*",
  ]

  runtime_jar_list_prefixes = [
    "${local.runtime_jar_parent_prefix}/*",
  ]

  default_arguments = merge(
    {
      "--TempDir"                          = local.temp_dir
      "--conf"                             = "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions"
      "--datalake-formats"                 = "iceberg"
      "--enable-continuous-cloudwatch-log" = "true"
      "--enable-metrics"                   = "true"
      "--extra-jars"                       = var.s3tables_runtime_jar_s3_uri
      "--extra-py-files" = join(",", [
        "s3://${var.artifact_bucket}/${aws_s3_object.bridge_logic.key}",
        "s3://${var.artifact_bucket}/${aws_s3_object.checkpoint.key}",
      ])
    },
    var.additional_default_arguments,
  )

  trigger_arguments = {
    "--CATALOG_NAME"     = var.catalog_name
    "--CHECKPOINT_URI"   = local.checkpoint_uri
    "--MODE"             = "append"
    "--NAMESPACE"        = var.namespace
    "--SOURCE_PATH"      = local.source_path
    "--TABLE_BUCKET_ARN" = var.table_bucket_arn
    "--TABLE_NAME"       = var.table_name
  }
}

resource "aws_iam_role" "glue" {
  name = local.glue_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "s3tables_full_access" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonS3TablesFullAccess"
}

resource "aws_iam_role_policy" "source_and_artifact_access" {
  name = "SourceAndArtifactBucketAccess"
  role = aws_iam_role.glue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SourceAndArtifactObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = [
          local.source_object_arn,
          local.artifact_object_arn,
          local.runtime_jar_arn,
        ]
      },
      {
        Sid    = "SourceAndArtifactBucketListing"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
        ]
        Resource = compact([
          "arn:${data.aws_partition.current.partition}:s3:::${var.source_bucket}",
          "arn:${data.aws_partition.current.partition}:s3:::${var.artifact_bucket}",
          "arn:${data.aws_partition.current.partition}:s3:::${local.runtime_jar_bucket}",
        ])
        Condition = {
          StringLike = {
            "s3:prefix" = concat(
              local.source_list_prefixes,
              local.artifact_list_prefixes,
              local.runtime_jar_list_prefixes,
            )
          }
        }
      },
      {
        Sid    = "LakeFormationGetDataAccess"
        Effect = "Allow"
        Action = [
          "lakeformation:GetDataAccess",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "snowflake_read" {
  count = var.create_snowflake_read_role ? 1 : 0

  name = local.snowflake_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      merge(
        {
          Effect = "Allow"
          Principal = {
            AWS = var.snowflake_iam_user_arn
          }
          Action = "sts:AssumeRole"
        },
        var.snowflake_external_id != null ? {
          Condition = {
            StringEquals = {
              "sts:ExternalId" = var.snowflake_external_id
            }
          }
        } : {},
      )
    ]
  })

  tags = var.tags

  lifecycle {
    precondition {
      condition     = var.snowflake_iam_user_arn != null
      error_message = "snowflake_iam_user_arn is required when create_snowflake_read_role is true."
    }

    precondition {
      condition     = var.snowflake_external_id != null || var.snowflake_bootstrap_trust_enabled
      error_message = "Set snowflake_external_id or explicitly enable snowflake_bootstrap_trust_enabled for the first apply."
    }
  }
}

resource "aws_iam_role_policy_attachment" "snowflake_s3tables_readonly" {
  count = var.create_snowflake_read_role ? 1 : 0

  role       = aws_iam_role.snowflake_read[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonS3TablesReadOnlyAccess"
}

resource "aws_iam_role_policy" "snowflake_glue_rest_read_access" {
  count = var.create_snowflake_read_role ? 1 : 0

  name = "SnowflakeGlueRestReadAccess"
  role = aws_iam_role.snowflake_read[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowGlueCatalogRead"
        Effect = "Allow"
        Action = [
          "glue:GetCatalog",
          "glue:GetCatalogs",
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetTableVersion",
          "glue:GetTableVersions",
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowLakeFormationRead"
        Effect = "Allow"
        Action = [
          "lakeformation:GetDataAccess",
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowS3TableDataRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_lakeformation_permissions" "snowflake_role_table_describe" {
  count = var.create_snowflake_read_role && var.grant_snowflake_lakeformation_permissions ? 1 : 0

  principal   = aws_iam_role.snowflake_read[0].arn
  permissions = ["DESCRIBE"]

  table {
    catalog_id    = local.lakeformation_catalog_id
    database_name = var.namespace
    name          = var.table_name
  }
}

resource "aws_lakeformation_permissions" "snowflake_role_table_select" {
  count = var.create_snowflake_read_role && var.grant_snowflake_lakeformation_permissions ? 1 : 0

  principal   = aws_iam_role.snowflake_read[0].arn
  permissions = ["SELECT"]

  table_with_columns {
    catalog_id    = local.lakeformation_catalog_id
    database_name = var.namespace
    name          = var.table_name
    wildcard      = true
  }
}

resource "aws_lakeformation_permissions" "snowflake_user_table_describe" {
  count = var.grant_snowflake_lakeformation_permissions && var.snowflake_iam_user_arn != null ? 1 : 0

  principal   = var.snowflake_iam_user_arn
  permissions = ["DESCRIBE"]

  table {
    catalog_id    = local.lakeformation_catalog_id
    database_name = var.namespace
    name          = var.table_name
  }
}

resource "aws_lakeformation_permissions" "snowflake_user_table_select" {
  count = var.grant_snowflake_lakeformation_permissions && var.snowflake_iam_user_arn != null ? 1 : 0

  principal   = var.snowflake_iam_user_arn
  permissions = ["SELECT"]

  table_with_columns {
    catalog_id    = local.lakeformation_catalog_id
    database_name = var.namespace
    name          = var.table_name
    wildcard      = true
  }
}

resource "aws_s3_object" "bridge" {
  bucket       = var.artifact_bucket
  key          = local.bridge_script
  source       = "${path.module}/../glue_job/bridge.py"
  etag         = filemd5("${path.module}/../glue_job/bridge.py")
  content_type = "text/x-python"

  tags = var.tags
}

resource "aws_s3_object" "bridge_logic" {
  bucket       = var.artifact_bucket
  key          = local.bridge_logic
  source       = "${path.module}/../glue_job/bridge_logic.py"
  etag         = filemd5("${path.module}/../glue_job/bridge_logic.py")
  content_type = "text/x-python"

  tags = var.tags
}

resource "aws_s3_object" "checkpoint" {
  bucket       = var.artifact_bucket
  key          = local.checkpoint_code
  source       = "${path.module}/../glue_job/checkpoint.py"
  etag         = filemd5("${path.module}/../glue_job/checkpoint.py")
  content_type = "text/x-python"

  tags = var.tags
}

resource "aws_glue_job" "this" {
  name     = local.glue_job_name
  role_arn = aws_iam_role.glue.arn

  glue_version = var.glue_version
  max_retries  = var.max_retries
  timeout      = var.timeout_minutes
  worker_type  = var.worker_type

  number_of_workers = var.number_of_workers

  execution_property {
    max_concurrent_runs = var.max_concurrent_runs
  }

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${var.artifact_bucket}/${aws_s3_object.bridge.key}"
  }

  default_arguments = local.default_arguments
  tags              = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.glue_service_role,
    aws_iam_role_policy_attachment.s3tables_full_access,
    aws_iam_role_policy.source_and_artifact_access,
  ]
}

resource "aws_glue_trigger" "schedule" {
  count = var.create_schedule ? 1 : 0

  name     = local.glue_trigger_name
  type     = "SCHEDULED"
  schedule = var.schedule_expression
  enabled  = var.schedule_enabled

  actions {
    job_name  = aws_glue_job.this.name
    arguments = local.trigger_arguments
  }

  tags = var.tags
}
