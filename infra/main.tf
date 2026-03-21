provider "aws" {
  region = "us-east-1"
}

# Variáveis

variable "infra_origin" {
  description = "Origem da infraestrutura"
  type        = string
  default     = "terraform"
}

variable "project_origin" {
  description = "Origem do projeto"
  type        = string
  default     = "fiap-tech_challenge"
}

variable "project_name" {
  description = "Nome do projeto"
  type        = string
  default     = "br_financial_market_data_lake"
}

variable "glue_default_arguments" {
  description = "Argumentos padrão para o Glue"
  type        = map(string)
  default = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-disable"
    "--enable-metrics"                   = "true"
    "--enable-observability-metrics"     = "true"
    "--enable-continuous-cloudwatch-log" = "false"
    "--enable-spark-ui"                  = "true"
    "--enable-glue-datacatalog"          = "true"
  }
}

# S3

resource "aws_s3_bucket" "fiap_datalake" {
  bucket = "fiap-tech-challenge-br-financial-market-data-lake"

  force_destroy = true # permite destruir bucket não vazio

  tags = {
    infra_origin   = var.infra_origin
    project_origin = var.project_origin
    project_name   = var.project_name
  }
}

resource "aws_s3_bucket_public_access_block" "bucket_security" {
  bucket = aws_s3_bucket.fiap_datalake.bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "raw_path" {
  bucket = aws_s3_bucket.fiap_datalake.bucket
  key    = "raw/"
}

resource "aws_s3_object" "refined_path" {
  bucket = aws_s3_bucket.fiap_datalake.bucket
  key    = "refined/"
}

resource "aws_s3_object" "scripts_path" {
  bucket = aws_s3_bucket.fiap_datalake.bucket
  key    = "glue/scripts/"
}

resource "aws_s3_object" "extract_logs_path" {
  bucket = aws_s3_bucket.fiap_datalake.bucket
  key    = "glue/extract/spark-ui/"
}

resource "aws_s3_object" "extract_temp_path" {
  bucket = aws_s3_bucket.fiap_datalake.bucket
  key    = "glue/extract/temp/"
}

resource "aws_s3_object" "transform_logs_path" {
  bucket = aws_s3_bucket.fiap_datalake.bucket
  key    = "glue/transform/spark-ui/"
}

resource "aws_s3_object" "transform_temp_path" {
  bucket = aws_s3_bucket.fiap_datalake.bucket
  key    = "glue/transform/temp/"
}

# IAM

## IAM ROLES

resource "aws_iam_role" "glue_etl_role" {
  name = "glue-etl-role"

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

  tags = {
    infra_origin   = var.infra_origin
    project_origin = var.project_origin
    project_name   = var.project_name
  }
}

## IAM POLICIES

resource "aws_iam_policy" "glue_s3_access" {
  name = "glue-s3-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.fiap_datalake.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.fiap_datalake.arn}/*"
      }
    ]
  })

  tags = {
    infra_origin   = var.infra_origin
    project_origin = var.project_origin
    project_name   = var.project_name
  }
}

## IAM POLICY ATTACHMENTS

resource "aws_iam_role_policy_attachment" "glue_service_policy" {
  role       = aws_iam_role.glue_etl_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "glue_s3_attach" {
  role       = aws_iam_role.glue_etl_role.name
  policy_arn = aws_iam_policy.glue_s3_access.arn
}

# GLUE

resource "aws_glue_job" "extract_job" {
  name     = "br-financial-market-extract-job"
  role_arn = aws_iam_role.glue_etl_role.arn

  command {
    name            = "glueetl" # Spark engine
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.fiap_datalake.bucket}/glue/scripts/extract_job.py"
  }

  default_arguments = merge(
    var.glue_default_arguments,
    {
      "--spark-event-logs-path"     = "s3://${aws_s3_bucket.fiap_datalake.bucket}/glue/extract/spark-ui/"
      "--TempDir"                   = "s3://${aws_s3_bucket.fiap_datalake.bucket}/glue/extract/temp/"
      "--additional-python-modules" = "yfinance==0.2.66"
      "--bucket_name"               = aws_s3_bucket.fiap_datalake.bucket
    }
  )

  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  max_retries       = 0
  timeout           = 30 # tempo máximo de execução em minutos

  execution_property {
    max_concurrent_runs = 1 # previne execução concorrente (ex.: agendamento + execução manual console)
  }

  tags = {
    infra_origin   = var.infra_origin
    project_origin = var.project_origin
    project_name   = var.project_name
  }
}
