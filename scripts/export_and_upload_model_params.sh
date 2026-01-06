#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "Exporting fraud scoring parameters..."
python ml_pipeline/export_fraud_scoring_parameters.py

cd "$REPO_ROOT/infra_terraform"
MODEL_BUCKET="$(terraform output -raw model_artifact_bucket)"
echo "Uploading to S3 bucket: $MODEL_BUCKET"

aws s3 cp \
  ../reports/fraud_scoring_parameters_latest.json \
  "s3://${MODEL_BUCKET}/fraud_scoring_parameters_latest.json" \
  --region us-east-1

echo "Model parameters upload completed."
