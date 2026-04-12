variable "name_prefix" {
  description = "Base name for Glue resources."
  type        = string
  default     = "sawmills-bigpanda-iceberg-bridge"
}

variable "environment" {
  description = "Environment suffix for resource naming."
  type        = string
}

variable "job_name" {
  description = "Optional explicit Glue job name."
  type        = string
  default     = null
}

variable "glue_role_name" {
  description = "Optional explicit IAM role name for the Glue job."
  type        = string
  default     = null
}

variable "trigger_name" {
  description = "Optional explicit Glue trigger name."
  type        = string
  default     = null
}

variable "artifact_bucket" {
  description = "Bucket that stores the Glue job scripts, temp dir, and runtime jar."
  type        = string
}

variable "artifact_prefix" {
  description = "Prefix inside the artifact bucket for Glue bridge assets."
  type        = string
}

variable "source_bucket" {
  description = "Bucket that stores the source Parquet files."
  type        = string
}

variable "source_prefix" {
  description = "Prefix inside the source bucket that contains the source Parquet files."
  type        = string
}

variable "table_bucket_arn" {
  description = "ARN of the target S3 Tables bucket."
  type        = string
}

variable "catalog_name" {
  description = "Spark catalog name for the direct S3 Tables path."
  type        = string
  default     = "s3tablesbp"
}

variable "namespace" {
  description = "Target Iceberg namespace."
  type        = string
}

variable "table_name" {
  description = "Target Iceberg table name."
  type        = string
}

variable "schedule_expression" {
  description = "Glue cron expression for ongoing append runs."
  type        = string
  default     = "cron(0/5 * * * ? *)"
}

variable "create_schedule" {
  description = "Whether to create the recurring Glue trigger."
  type        = bool
  default     = true
}

variable "schedule_enabled" {
  description = "Whether the recurring trigger should start activated."
  type        = bool
  default     = true
}

variable "glue_version" {
  description = "Glue runtime version."
  type        = string
  default     = "5.0"
}

variable "worker_type" {
  description = "Glue worker type."
  type        = string
  default     = "G.1X"
}

variable "number_of_workers" {
  description = "Glue worker count."
  type        = number
  default     = 2
}

variable "timeout_minutes" {
  description = "Glue job timeout in minutes."
  type        = number
  default     = 480
}

variable "max_retries" {
  description = "Glue job retry count."
  type        = number
  default     = 0
}

variable "max_concurrent_runs" {
  description = "Max concurrent Glue runs for the job."
  type        = number
  default     = 1
}

variable "s3tables_runtime_jar_s3_uri" {
  description = "S3 URI for the S3 Tables Iceberg runtime jar."
  type        = string
}

variable "additional_default_arguments" {
  description = "Additional Glue default arguments merged on top of the baseline runtime arguments."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Common tags applied to managed resources."
  type        = map(string)
  default     = {}
}

variable "create_snowflake_read_role" {
  description = "Whether to create the AWS-side Snowflake read role for Glue REST / S3 Tables access."
  type        = bool
  default     = false
}

variable "snowflake_read_role_name" {
  description = "Optional explicit IAM role name for the Snowflake read role."
  type        = string
  default     = null
}

variable "snowflake_iam_user_arn" {
  description = "Snowflake-managed AWS IAM user ARN from DESCRIBE INTEGRATION."
  type        = string
  default     = null
}

variable "snowflake_external_id" {
  description = "Snowflake external ID from DESCRIBE INTEGRATION. Leave null only during the initial bootstrap apply."
  type        = string
  default     = null
}

variable "snowflake_bootstrap_trust_enabled" {
  description = "Allow bootstrap trust without an external ID so the role can exist before Snowflake generates one."
  type        = bool
  default     = false
}

variable "grant_snowflake_lakeformation_permissions" {
  description = "Whether to grant DESCRIBE and SELECT on the target S3 Tables table to the Snowflake principals."
  type        = bool
  default     = false
}
