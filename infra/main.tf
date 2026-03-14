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

# S3

resource "aws_s3_bucket" "fiap_datalake" {
  bucket = "fiap-tech-challenge-br-financial-market-data-lake"

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
  key    = "scripts/"
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
