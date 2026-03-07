provider "aws" {
  region = "us-east-1"
}

variable "origin" {
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
  bucket = "${var.origin}-${var.project_name}"

  tags = {
    Origin  = var.origin
    Project = var.project_name
  }
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
