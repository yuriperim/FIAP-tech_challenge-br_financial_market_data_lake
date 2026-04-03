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

# Artefato (data)

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "../scripts/transform_trigger.py"
  output_path = "../scripts/transform_trigger.zip"
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

resource "aws_s3_object" "tickers_json" {
  bucket = aws_s3_bucket.fiap_datalake.bucket
  key    = "glue/scripts/tickers.json"
  source = "../scripts/tickers.json"
  etag   = filemd5("../scripts/tickers.json") # garante upload se o json for modificado
}

resource "aws_s3_object" "extract_script" {
  bucket = aws_s3_bucket.fiap_datalake.bucket
  key    = "glue/scripts/extract_job.py"
  source = "../scripts/extract_job.py"
  etag   = filemd5("../scripts/extract_job.py") # garante upload se o script for modificado
}

resource "aws_s3_object" "transform_script" {
  bucket = aws_s3_bucket.fiap_datalake.bucket
  key    = "glue/scripts/transform_job.py"
  source = "../scripts/transform_job.py"
  etag   = filemd5("../scripts/transform_job.py") # garante upload se o script for modificado
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

resource "aws_s3_object" "lambda_path" {
  bucket = aws_s3_bucket.fiap_datalake.bucket
  key    = "lambda/"
}

resource "aws_s3_object" "trigger_script" {
  bucket = aws_s3_bucket.fiap_datalake.bucket
  key    = "lambda/transform_trigger.zip"
  source = data.archive_file.lambda_zip.output_path
  etag   = filemd5(data.archive_file.lambda_zip.output_path) # garante upload se o script for modificado
}

resource "aws_s3_object" "queries_path" {
  bucket = aws_s3_bucket.fiap_datalake.bucket
  key    = "athena/"
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

resource "aws_iam_role" "lambda_trigger_role" {
  name = "lambda-trigger-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
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

resource "aws_iam_policy" "lambda_glue_run" {
  name = "lambda-glue-run"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:StartJobRun"
        ]
        Resource = aws_glue_job.transform_job.arn # transform_job é definido posteriormente (dependência implícita)
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

resource "aws_iam_role_policy_attachment" "lambda_basic_policy" {
  role       = aws_iam_role.lambda_trigger_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_glue_attach" {
  role       = aws_iam_role.lambda_trigger_role.name
  policy_arn = aws_iam_policy.lambda_glue_run.arn
}

# GLUE

## Extract

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
      "--additional-python-modules" = "urllib3==1.26.20,yfinance==0.2.66" # urllib3<2 especificada por compatibilidade com boto3
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

resource "aws_glue_trigger" "extract_job_schedule" {
  name     = "br-financial-market-extract-job-schedule"
  type     = "SCHEDULED"
  schedule = "cron(0 5 * * ? *)" # diariamente às 05:00 UTC+00:00 (02:00 UTC-03:00)

  actions {
    job_name = aws_glue_job.extract_job.name
  }
}

## Transform

resource "aws_glue_job" "transform_job" {
  name     = "br-financial-market-transform-job"
  role_arn = aws_iam_role.glue_etl_role.arn

  command {
    name            = "glueetl" # Spark engine
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.fiap_datalake.bucket}/glue/scripts/transform_job.py"
  }

  default_arguments = merge(
    var.glue_default_arguments,
    {
      "--spark-event-logs-path" = "s3://${aws_s3_bucket.fiap_datalake.bucket}/glue/transform/spark-ui/"
      "--TempDir"               = "s3://${aws_s3_bucket.fiap_datalake.bucket}/glue/transform/temp/"
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

# LAMBDA

resource "aws_lambda_function" "transform_trigger" {
  function_name = "br-financial-market-transform-trigger"
  role          = aws_iam_role.lambda_trigger_role.arn

  # -> teoricamente desnecessário, mas garante que a lambda seja criada após upload do script (evita erro de script não encontrado no primeiro deploy)
  depends_on = [
    aws_s3_object.trigger_script
  ]

  handler = "transform_trigger.lambda_handler" # <nome_arquivo>.<nome_funcao>
  runtime = "python3.12"

  s3_bucket        = aws_s3_bucket.fiap_datalake.bucket
  s3_key           = aws_s3_object.trigger_script.key
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256 # garante "redeploy" lambda se o script for modificado

  tags = {
    infra_origin   = var.infra_origin
    project_origin = var.project_origin
    project_name   = var.project_name
  }
}

# -> lambda permite ser chamada pelo S3
resource "aws_lambda_permission" "transform_trigger_permission" {
  statement_id  = "transform-trigger-permission"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.transform_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.fiap_datalake.arn
}

# -> S3 notifica lambda (um bucket suporta apenas uma configuração de notificação)
resource "aws_s3_bucket_notification" "transform_trigger_notification" {
  bucket = aws_s3_bucket.fiap_datalake.bucket

  lambda_function {
    lambda_function_arn = aws_lambda_function.transform_trigger.arn

    events = [
      "s3:ObjectCreated:*"
    ]
    filter_prefix = "raw/stocks/"
    filter_suffix = "_SUCCESS"
  }

  depends_on = [
    aws_lambda_permission.transform_trigger_permission
  ]
}

# ATHENA

# -> na ausência de configuração de um workgroup, é utilizado o workgroup padrão "primary"
resource "aws_athena_workgroup" "br_financial_market_data_lake_workgroup" {
  name = "br-financial-market-data-lake-workgroup"

  configuration {
    enforce_workgroup_configuration = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.fiap_datalake.bucket}/athena/"
    }
  }

  force_destroy = true # permite destruir workgroup não vazio (com queries salvas, por exemplo)

  tags = {
    infra_origin   = var.infra_origin
    project_origin = var.project_origin
    project_name   = var.project_name
  }
}
