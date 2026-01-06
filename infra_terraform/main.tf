terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  tags = {
    Project     = var.project_name
    Environment = var.environment
  }

  validation_zip_path = "${path.module}/../build/lambda_packages/transaction_validation_service.zip"
  scoring_zip_path    = "${path.module}/../build/lambda_packages/transaction_scoring_service.zip"

  validation_lambda_name = "${local.name_prefix}-lambda-validate-transaction"
  scoring_lambda_name    = "${local.name_prefix}-lambda-score-transaction"

  api_name = "${local.name_prefix}-api-transaction-services"
}


resource "random_id" "model_bucket_suffix" {
  byte_length = 3
}

# ---------------------------
# S3: model artifact bucket
# ---------------------------
resource "aws_s3_bucket" "model_artifacts" {
  bucket        = "${local.name_prefix}-model-artifacts-${random_id.model_bucket_suffix.hex}"
  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "model_artifacts" {
  bucket                  = aws_s3_bucket.model_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------
# IAM: Lambda execution roles
# ---------------------------
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_validate_transaction_role" {
  name               = "${local.name_prefix}-role-lambda-validate-transaction"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.tags
}

resource "aws_iam_role" "lambda_score_transaction_role" {
  name               = "${local.name_prefix}-role-lambda-score-transaction"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.tags
}

# Basic logging
resource "aws_iam_role_policy_attachment" "validate_basic_logging" {
  role       = aws_iam_role.lambda_validate_transaction_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "score_basic_logging" {
  role       = aws_iam_role.lambda_score_transaction_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Allow scoring lambda to read model artifacts from S3 (we’ll use later in Step 6)
data "aws_iam_policy_document" "score_s3_read" {
  statement {
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.model_artifacts.arn,
      "${aws_s3_bucket.model_artifacts.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "score_s3_read_policy" {
  name   = "${local.name_prefix}-policy-score-s3-read"
  policy = data.aws_iam_policy_document.score_s3_read.json
  tags   = local.tags
}

resource "aws_iam_role_policy_attachment" "score_s3_read_attach" {
  role       = aws_iam_role.lambda_score_transaction_role.name
  policy_arn = aws_iam_policy.score_s3_read_policy.arn
}

# ---------------------------
# CloudWatch log groups (set retention)
# ---------------------------
resource "aws_cloudwatch_log_group" "validate_log_group" {
  name              = "/aws/lambda/${local.validation_lambda_name}"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

resource "aws_cloudwatch_log_group" "score_log_group" {
  name              = "/aws/lambda/${local.scoring_lambda_name}"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

# ---------------------------
# Lambda: validation
# ---------------------------
resource "aws_lambda_function" "validate_transaction" {
  function_name = local.validation_lambda_name
  role          = aws_iam_role.lambda_validate_transaction_role.arn

  filename         = local.validation_zip_path
  source_code_hash = filebase64sha256(local.validation_zip_path)

  runtime = "python3.12"
  handler = "lambda_handler_validate_transaction.handler"
  timeout = 10
  memory_size = 256

  tags = local.tags
  depends_on = [aws_cloudwatch_log_group.validate_log_group]
}

# ---------------------------
# Lambda: scoring
# NOTE: currently loads local model artifact, but Lambda won’t have it.
# In Step 6 we will update code to download model from S3 on cold start.
# ---------------------------
resource "aws_lambda_function" "score_transaction" {
  function_name = local.scoring_lambda_name
  role          = aws_iam_role.lambda_score_transaction_role.arn

  filename         = local.scoring_zip_path
  source_code_hash = filebase64sha256(local.scoring_zip_path)

  runtime = "python3.12"
  handler = "lambda_handler_score_transaction.handler"
  timeout = 20
  memory_size = 512

  environment {
    variables = {
      MODEL_BUCKET = aws_s3_bucket.model_artifacts.bucket
      MODEL_KEY    = "fraud_scoring_parameters_latest.json"
    }
  }

  tags = local.tags
  depends_on = [aws_cloudwatch_log_group.score_log_group]
}

# ---------------------------
# API Gateway HTTP API
# ---------------------------
resource "aws_apigatewayv2_api" "http_api" {
  name          = local.api_name
  protocol_type = "HTTP"
  tags          = local.tags
}

# Integrations
resource "aws_apigatewayv2_integration" "validate_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.validate_transaction.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "score_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.score_transaction.invoke_arn
  payload_format_version = "2.0"
}

# Routes
resource "aws_apigatewayv2_route" "validate_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /validate-transaction"
  target    = "integrations/${aws_apigatewayv2_integration.validate_integration.id}"
}

resource "aws_apigatewayv2_route" "score_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /score-transaction"
  target    = "integrations/${aws_apigatewayv2_integration.score_integration.id}"
}

# Stage
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
  tags        = local.tags
}

# Lambda permissions for API Gateway
resource "aws_lambda_permission" "allow_api_validate" {
  statement_id  = "AllowInvokeFromApiGatewayValidate"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.validate_transaction.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_api_score" {
  statement_id  = "AllowInvokeFromApiGatewayScore"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.score_transaction.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
