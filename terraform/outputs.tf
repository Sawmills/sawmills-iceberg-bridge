output "glue_job_name" {
  description = "Glue job name."
  value       = aws_glue_job.this.name
}

output "glue_job_role_arn" {
  description = "IAM role ARN used by the Glue job."
  value       = aws_iam_role.glue.arn
}

output "snowflake_read_role_arn" {
  description = "IAM role ARN for the Snowflake Glue REST read path when enabled."
  value       = try(aws_iam_role.snowflake_read[0].arn, null)
}

output "lakeformation_catalog_id" {
  description = "Bucket-scoped Glue/Lake Formation catalog ID derived from table_bucket_arn."
  value       = local.lakeformation_catalog_id
}

output "glue_trigger_name" {
  description = "Glue trigger name when create_schedule is enabled."
  value       = try(aws_glue_trigger.schedule[0].name, null)
}

output "source_path" {
  description = "Resolved source Parquet path."
  value       = local.source_path
}

output "checkpoint_uri" {
  description = "Resolved checkpoint manifest URI."
  value       = local.checkpoint_uri
}

output "bridge_script_s3_uri" {
  description = "S3 URI for the uploaded bridge.py script."
  value       = "s3://${var.artifact_bucket}/${aws_s3_object.bridge.key}"
}

output "bridge_logic_s3_uri" {
  description = "S3 URI for the uploaded bridge_logic.py helper."
  value       = "s3://${var.artifact_bucket}/${aws_s3_object.bridge_logic.key}"
}

output "checkpoint_helper_s3_uri" {
  description = "S3 URI for the uploaded checkpoint.py helper."
  value       = "s3://${var.artifact_bucket}/${aws_s3_object.checkpoint.key}"
}

output "manual_replace_arguments" {
  description = "Arguments map for a one-off replace run."
  value = {
    "--CATALOG_NAME"     = var.catalog_name
    "--CHECKPOINT_URI"   = local.checkpoint_uri
    "--MODE"             = "replace"
    "--NAMESPACE"        = var.namespace
    "--SOURCE_PATH"      = local.source_path
    "--TABLE_BUCKET_ARN" = var.table_bucket_arn
    "--TABLE_NAME"       = var.table_name
  }
}
