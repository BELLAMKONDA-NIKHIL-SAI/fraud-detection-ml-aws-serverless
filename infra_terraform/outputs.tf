/* Base URL of the API Gateway HTTP API.
This is the root endpoint used by all exposed API routes. */
output "api_base_url" {
  value       = aws_apigatewayv2_api.http_api.api_endpoint
  description = "Base URL of the API Gateway HTTP API"
}

/* Full endpoint URL for validating transactions.
This endpoint is expected to receive POST requests for transaction validation logic. */
output "validate_transaction_url" {
  value       = "${aws_apigatewayv2_api.http_api.api_endpoint}/validate-transaction"
  description = "POST endpoint for transaction validation"
}

/* Full endpoint URL for scoring transactions.
This endpoint is expected to receive POST requests for transaction scoring logic. */
output "score_transaction_url" {
  value       = "${aws_apigatewayv2_api.http_api.api_endpoint}/score-transaction"
  description = "POST endpoint for transaction scoring"
}

/* Name of the S3 bucket used to store ML model artifacts.
This bucket typically contains trained models, metadata, or versioned artifacts. */
output "model_artifact_bucket" {
  value       = aws_s3_bucket.model_artifacts.bucket
  description = "S3 bucket for model artifacts"
}
