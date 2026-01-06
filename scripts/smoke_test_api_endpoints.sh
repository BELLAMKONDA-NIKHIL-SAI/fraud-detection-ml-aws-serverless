#!/usr/bin/env bash
set -euo pipefail

echo "=== Smoke test: Fraud Detection API ==="

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT/infra_terraform"

API_BASE_URL="$(terraform output -raw api_base_url)"
echo "API Base URL: $API_BASE_URL"

echo ""
echo "--- Testing /validate-transaction ---"
curl -s -X POST "$API_BASE_URL/validate-transaction" \
  -H "Content-Type: application/json" \
  -d @../scripts/sample_requests/validate_transaction_example.json \
  | tee /tmp/validate_response.json | jq .

if ! jq -e '.is_valid == true' /tmp/validate_response.json > /dev/null; then
  echo "Validation endpoint failed"
  exit 1
fi

echo ""
echo "--- Testing /score-transaction ---"
curl -s -X POST "$API_BASE_URL/score-transaction" \
  -H "Content-Type: application/json" \
  -d @../scripts/sample_requests/score_transaction_example.json \
  | tee /tmp/score_response.json | jq .

jq -e '.fraud_probability != null' /tmp/score_response.json > /dev/null
jq -e '.fraud_label != null' /tmp/score_response.json > /dev/null

echo ""
echo "Smoke tests PASSED"
