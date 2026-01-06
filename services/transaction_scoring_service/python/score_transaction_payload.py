from __future__ import annotations

import math
import uuid
from typing import Any, Dict, List

from load_fraud_model_artifact import load_scoring_parameters


def _sigmoid(x: float) -> float:
    # stable-ish sigmoid
    if x >= 0:
        z = math.exp(-x)
        return 1.0 / (1.0 + z)
    else:
        z = math.exp(x)
        return z / (1.0 + z)


def _standardize(value: float, mean: float, scale: float) -> float:
    if scale == 0:
        return 0.0
    return (value - mean) / scale


def _to_float(v: Any, default: float = 0.0) -> float:
    try:
        return float(v)
    except Exception:
        return default


def _build_feature_vector(txn: Dict[str, Any], params: Dict[str, Any]) -> List[float]:
    numeric_features: List[str] = params["numeric_features"]
    categorical_features: List[str] = params["categorical_features"]
    mean: List[float] = params["numeric_scaler"]["mean"]
    scale: List[float] = params["numeric_scaler"]["scale"]
    one_hot_categories: Dict[str, List[Any]] = params["one_hot_categories"]

    # numeric standardized
    vec: List[float] = []
    for i, f in enumerate(numeric_features):
        x = _to_float(txn.get(f, 0.0), 0.0)
        vec.append(_standardize(x, float(mean[i]), float(scale[i])))

    # categoricals one-hot (unknown -> all zeros)
    for f in categorical_features:
        cats = one_hot_categories.get(f, [])
        val = txn.get(f)

        # Normalize common cases
        if isinstance(val, str):
            if f in ("currency", "country"):
                val = val.strip().upper()
            else:
                val = val.strip().lower()

        # Booleans in JSON remain bool; categories store bool for is_international
        for c in cats:
            vec.append(1.0 if val == c else 0.0)

    return vec


def score_transaction_request(payload: Dict[str, Any]) -> Dict[str, Any]:
    req_id = payload.get("request_id") if isinstance(payload.get("request_id"), str) else None
    request_id = req_id or str(uuid.uuid4())

    txn = payload.get("transaction")
    if not isinstance(txn, dict):
        return {
            "request_id": request_id,
            "fraud_probability": None,
            "fraud_label": None,
            "model_version": None,
            "decision_threshold": None,
            "error": "Missing or invalid 'transaction' object",
        }

    params = load_scoring_parameters()

    coef: List[float] = params["logistic_regression"]["coefficients"]
    intercept: float = float(params["logistic_regression"]["intercept"])
    threshold: float = float(params["decision_threshold"])

    x = _build_feature_vector(txn, params)
    if len(x) != len(coef):
        return {
            "request_id": request_id,
            "fraud_probability": None,
            "fraud_label": None,
            "model_version": params.get("model_version"),
            "decision_threshold": threshold,
            "error": f"Feature length mismatch: got {len(x)} expected {len(coef)}",
        }

    logit = intercept + sum(float(w) * float(v) for w, v in zip(coef, x))
    proba = _sigmoid(logit)
    label = int(proba >= threshold)

    return {
        "request_id": request_id,
        "fraud_probability": round(float(proba), 6),
        "fraud_label": label,
        "model_version": params.get("model_version"),
        "decision_threshold": threshold,
    }
