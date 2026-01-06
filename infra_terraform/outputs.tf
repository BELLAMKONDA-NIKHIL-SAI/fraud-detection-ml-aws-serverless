output "api_base_url" {
  value       = aws_apigatewayv2_api.http_api.api_endpoint
  description = "Base URL of the API Gateway HTTP API"
}

output "validate_transaction_url" {
  value       = "${aws_apigatewayv2_api.http_api.api_endpoint}/validate-transaction"
  description = "POST endpoint for transaction validation"
}

output "score_transaction_url" {
  value       = "${aws_apigatewayv2_api.http_api.api_endpoint}/score-transaction"
  description = "POST endpoint for transaction scoring"
}

output "model_artifact_bucket" {
  value       = aws_s3_bucket.model_artifacts.bucket
  description = "S3 bucket for model artifacts"
}
