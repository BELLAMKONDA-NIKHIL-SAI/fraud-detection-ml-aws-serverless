# ----------------------------
# Terraform + provider setup
# ----------------------------
terraform {
  # This prevents running with older Terraform versions that might not support features we use.
  required_version = ">= 1.5.0"

  # Pin providers we rely on.
  # - aws: creates AWS resources
  # - random: generates a random suffix so bucket names stay globally unique
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

# Tells Terraform which AWS region to deploy into.
# (We pass this from envs/dev/terraform.tfvars)
provider "aws" {
  region = var.aws_region
}

# ----------------------------
# Reusable naming + tagging
# ----------------------------
locals {
  # Build consistent names like: fraudml-dev-...
  name_prefix = "${var.project_name}-${var.environment}"

  # Tags help you filter resources by project and environment in AWS.
  tags = {
    Project     = var.project_name
    Environment = var.environment
  }

  # These point to your locally built Lambda zip files.
  # Terraform uploads these zips to Lambda when you apply.
  validation_zip_path = "${path.module}/../build/lambda_packages/transaction_validation_service.zip"
  scoring_zip_path    = "${path.module}/../build/lambda_packages/transaction_scoring_service.zip"

  # Final Lambda function names inside AWS.
  validation_lambda_name = "${local.name_prefix}-lambda-validate-transaction"
  scoring_lambda_name    = "${local.name_prefix}-lambda-score-transaction"

  # API Gateway name inside AWS.
  api_name = "${local.name_prefix}-api-transaction-services"
}

# ----------------------------
# Random suffix for unique resources
# ----------------------------
resource "random_id" "model_bucket_suffix" {
  # S3 bucket names are global, so we add a small random suffix to avoid conflicts.
  byte_length = 3
}

# ----------------------------
# S3 bucket to store model artifacts
# ----------------------------
resource "aws_s3_bucket" "model_artifacts" {
  # Stores ML model parameters (JSON) used by the scoring Lambda.
  bucket        = "${local.name_prefix}-model-artifacts-${random_id.model_bucket_suffix.hex}"

  # Allows terraform destroy to remove the bucket even if it has objects in it.
  # (Very useful for demo environments.)
  force_destroy = true

  tags = local.tags
}

resource "aws_s3_bucket_public_access_block" "model_artifacts" {
  # This ensures the bucket cannot be made public accidentally.
  bucket                  = aws_s3_bucket.model_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ----------------------------
# IAM: allow Lambda service to assume execution roles
# ----------------------------
data "aws_iam_policy_document" "lambda_assume_role" {
  # This trust policy says: "AWS Lambda is allowed to assume this role"
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# IAM role used by the validation Lambda (permissions attached below)
resource "aws_iam_role" "lambda_validate_transaction_role" {
  name               = "${local.name_prefix}-role-lambda-validate-transaction"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.tags
}

# IAM role used by the scoring Lambda (permissions attached below)
resource "aws_iam_role" "lambda_score_transaction_role" {
  name               = "${local.name_prefix}-role-lambda-score-transaction"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.tags
}

# ----------------------------
# IAM: basic CloudWatch logging for both Lambdas
# ----------------------------
# This gives each Lambda permission to write logs to CloudWatch.
resource "aws_iam_role_policy_attachment" "validate_basic_logging" {
  role       = aws_iam_role.lambda_validate_transaction_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "score_basic_logging" {
  role       = aws_iam_role.lambda_score_transaction_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ----------------------------
# IAM: allow scoring Lambda to read model artifacts from S3
# ----------------------------
# Scoring Lambda needs read access to the bucket to download model parameters.
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

# ----------------------------
# CloudWatch Log Groups
# ----------------------------
# Creating log groups explicitly lets you set retention.
# Otherwise logs could be kept forever and cost more over time.
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

# ----------------------------
# Lambda: validation microservice
# ----------------------------
resource "aws_lambda_function" "validate_transaction" {
  # Deployed Lambda function name
  function_name = local.validation_lambda_name

  # Which IAM role it uses at runtime
  role = aws_iam_role.lambda_validate_transaction_role.arn

  # Zip file for the Lambda code (created by your packaging script)
  filename         = local.validation_zip_path
  source_code_hash = filebase64sha256(local.validation_zip_path)

  # Runtime and handler entrypoint in the zip
  runtime = "python3.12"
  handler = "lambda_handler_validate_transaction.handler"

  # Runtime settings
  timeout     = 10
  memory_size = 256

  tags = local.tags

  # Ensures log group exists before Lambda runs and tries to write logs.
  depends_on = [aws_cloudwatch_log_group.validate_log_group]
}

# ----------------------------
# Lambda: scoring microservice
# ----------------------------
resource "aws_lambda_function" "score_transaction" {
  # Deployed Lambda function name
  function_name = local.scoring_lambda_name

  # Which IAM role it uses at runtime
  role = aws_iam_role.lambda_score_transaction_role.arn

  # Zip file for the Lambda code (created by your packaging script)
  filename         = local.scoring_zip_path
  source_code_hash = filebase64sha256(local.scoring_zip_path)

  # Runtime and handler entrypoint in the zip
  runtime = "python3.12"
  handler = "lambda_handler_score_transaction.handler"

  # Scoring typically needs a bit more time/memory than validation
  timeout     = 20
  memory_size = 512

  # These environment variables tell the scoring Lambda where the model parameters live.
  environment {
    variables = {
      MODEL_BUCKET = aws_s3_bucket.model_artifacts.bucket
      MODEL_KEY    = "fraud_scoring_parameters_latest.json"
    }
  }

  tags = local.tags

  depends_on = [aws_cloudwatch_log_group.score_log_group]
}

# ----------------------------
# API Gateway (HTTP API)
# ----------------------------
resource "aws_apigatewayv2_api" "http_api" {
  # This is the public entrypoint for clients to call your services.
  name          = local.api_name
  protocol_type = "HTTP"
  tags          = local.tags
}

# ----------------------------
# API Gateway Integrations
# ----------------------------
# Integrations are how API Gateway talks to Lambda.
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

# ----------------------------
# API Gateway Routes
# ----------------------------
# These define the URLs that clients call.
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

# ----------------------------
# API Gateway Stage
# ----------------------------
# $default stage means you don't need a stage name in the URL.
# auto_deploy=true deploys route changes immediately.
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
  tags        = local.tags
}

# ----------------------------
# Allow API Gateway to invoke the Lambdas
# ----------------------------
# Without these permissions, API Gateway would get 403 when trying to call Lambda.
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
