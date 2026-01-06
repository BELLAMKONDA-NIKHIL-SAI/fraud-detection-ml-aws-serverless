#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build/lambda_packages"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

package_service () {
  local service_dir="$1"
  local output_zip="$2"

  echo "Packaging: $service_dir -> $output_zip"
  pushd "$service_dir" >/dev/null

  # Ensure fresh vendor directory
  rm -rf python
  mkdir -p python

  # Install deps into python/ for Lambda zip
  if [ -f requirements.txt ]; then
    pip install -r requirements.txt -t python >/dev/null
  fi

  # Copy service python files
  cp ./*.py python/

  # Copy json assets (schemas, config)
  cp ./*.json python/ 2>/dev/null || true

  # Create zip (Lambda expects code at root for handler import)
  pushd python >/dev/null
  zip -r "$output_zip" . >/dev/null
  popd >/dev/null

  popd >/dev/null
}

package_service "$PROJECT_ROOT/services/transaction_validation_service" \
  "$BUILD_DIR/transaction_validation_service.zip"

package_service "$PROJECT_ROOT/services/transaction_scoring_service" \
  "$BUILD_DIR/transaction_scoring_service.zip"

echo "Done. Zips created in: $BUILD_DIR"
ls -la "$BUILD_DIR"
