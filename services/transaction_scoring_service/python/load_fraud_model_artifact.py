from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Dict, Optional

try:
    import boto3  # available in Lambda runtime
except Exception:
    boto3 = None


_CACHED_PARAMS: Optional[Dict[str, Any]] = None


def _lambda_tmp_params_path() -> Path:
    return Path("/tmp/fraud_scoring_parameters_latest.json")


def _download_from_s3(bucket: str, key: str, dest: Path) -> None:
    if boto3 is None:
        raise RuntimeError("boto3 not available. This function is intended for AWS Lambda runtime.")
    dest.parent.mkdir(parents=True, exist_ok=True)
    boto3.client("s3").download_file(bucket, key, str(dest))


def load_scoring_parameters() -> Dict[str, Any]:
    """
    Loads scoring parameters.

    Priority:
    1) Lambda: download from S3 (MODEL_BUCKET/MODEL_KEY) to /tmp and cache in memory
    2) Local dev: read from reports/fraud_scoring_parameters_latest.json
    """
    global _CACHED_PARAMS
    if _CACHED_PARAMS is not None:
        return _CACHED_PARAMS

    bucket = os.getenv("MODEL_BUCKET")
    key = os.getenv("MODEL_KEY")

    if bucket and key:
        tmp = _lambda_tmp_params_path()
        if not tmp.exists():
            _download_from_s3(bucket, key, tmp)
        _CACHED_PARAMS = json.loads(tmp.read_text(encoding="utf-8"))
        return _CACHED_PARAMS

    repo_root = Path(__file__).resolve().parents[2]
    local_path = repo_root / "reports" / "fraud_scoring_parameters_latest.json"
    if not local_path.exists():
        raise FileNotFoundError(f"Missing {local_path}. Run: python ml_pipeline/export_fraud_scoring_parameters.py")

    _CACHED_PARAMS = json.loads(local_path.read_text(encoding="utf-8"))
    return _CACHED_PARAMS
